import Foundation

/// A language sandboxed code is written in, with the image and interpreter that run it.
enum SandboxLanguage: String, CaseIterable, Sendable {
    /// Python 3.13 with only the standard library.
    case python
    /// Node.js 22 with only its built-in modules.
    case node
    /// Alpine Linux's BusyBox `sh`.
    case shell

    /// The container image the code runs in.
    var image: String {
        switch self {
        case .python: "python:3.13-slim"
        case .node: "node:22-slim"
        case .shell: "alpine:3"
        }
    }

    /// The program inside the image that runs the code file.
    var interpreter: String {
        switch self {
        case .python: "python3"
        case .node: "node"
        case .shell: "sh"
        }
    }

    /// The name the code is saved under in the work folder.
    var codeFileName: String {
        switch self {
        case .python: "main.py"
        case .node: "main.js"
        case .shell: "main.sh"
        }
    }
}

/// Runs code in a throwaway Linux container through Apple's `container` CLI, sharing only a per-run work folder.
struct RunInSandboxTool: Tool {
    /// Where the work folder is mounted inside the container.
    private static let containerWorkFolder = "/work"
    /// Memory the container may use.
    private static let memoryLimit = "2g"
    /// CPUs the container may use.
    private static let cpuLimit = "2"
    /// Most output characters returned to the model.
    static let outputLimit = 15_000
    /// Seconds the code may run when the model doesn't say.
    private static let defaultTimeout = 120
    /// Longest the code may run, in seconds.
    private static let maximumTimeout = 600
    /// Extra seconds allowed for starting the container and downloading its image the first time.
    private static let startupAllowance: TimeInterval = 300
    /// Most new file paths listed in the result.
    private static let listedFileLimit = 30
    /// Where the `container` CLI is installed: its signed installer, then Homebrew.
    private static let cliPaths = ["/usr/local/bin/container", "/opt/homebrew/bin/container"]
    /// Parent of the per-run work folders.
    private static let workFolders = URL.applicationSupportDirectory.appending(path: "macobar/sandbox")
    /// Parent of the per-run folders that new files are copied to.
    private static let resultFolders = URL.downloadsDirectory.appending(path: "Macie Sandbox")
    /// Runs the code under a time limit and prints its exit status last, so the status survives output capping.
    private static let runnerScript = #"timeout "$1" "$2" "$3"; printf '\n[exit status %s]\n' "$?""#

    /// Name the model calls it by.
    let name = "run_in_sandbox"
    /// When to call it and what it returns.
    let description = """
        Runs code in an isolated Linux container that can't touch the Mac; use it instead of run_shell to calculate, \
        analyse data, convert files or plot charts. Minimal images: standard library only, or install packages from the \
        code. Input files are copied to /work (originals unchanged); save results there. Returns the output, \
        "[exit status N]" (124 or 143 = timed out) and the ~/Downloads paths of new files.
        """

    /// The language, code, input files and time limit.
    var parameters: JSONValue {
        Schema.object([
            "language": Schema.oneOf(SandboxLanguage.allCases.map(\.rawValue), "Code language."),
            "code": Schema.string("The complete program."),
            "files": Schema.strings("Mac file or folder paths to copy into /work; ~ allowed."),
            "timeout_seconds": Schema.integer("Seconds, 1-600; default 120."),
        ], required: ["language", "code"])
    }

    /// Code alone asks once; with the user's files it asks every time, since the container can reach the internet.
    func risk(for input: ToolInput) -> ToolRisk {
        input.strings("files").isEmpty ? .confirmOnce : .confirmEveryTime
    }

    /// Its result is whatever the code printed, which can include downloads and the user's files.
    func readsOutsideContent(for input: ToolInput) -> Bool {
        true
    }

    /// Names the language.
    func activity(for input: ToolInput) -> String {
        switch SandboxLanguage(rawValue: input.string("language") ?? "") {
        case .python: "Running Python in a sandbox"
        case .node: "Running JavaScript in a sandbox"
        case .shell: "Running a shell script in a sandbox"
        case nil: "Running code in a sandbox"
        }
    }

    /// Prepares a work folder, runs the container, saves new files to Downloads and cleans up.
    func run(_ input: ToolInput) async throws -> String {
        let languageName = try input.requiredString("language")
        guard let language = SandboxLanguage(rawValue: languageName) else {
            throw ToolError("Unknown language \"\(languageName)\". Use one of: \(SandboxLanguage.allCases.map(\.rawValue).joined(separator: ", ")).")
        }
        guard let code = input.rawString("code"), !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolError("Missing required argument \"code\".")
        }
        let timeout = min(max(input.integer("timeout_seconds") ?? Self.defaultTimeout, 1), Self.maximumTimeout)
        let cli = try await Self.readyCLI()

        let workFolder = Self.workFolders.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: workFolder) }
        try Self.prepare(workFolder, code: code, language: language, inputs: input.strings("files"))
        let filesBefore = Self.filePaths(in: workFolder)

        let output: String
        do {
            output = try await ProcessRunner.run(
                cli,
                Self.containerArguments(language: language, workFolder: workFolder, timeoutSeconds: timeout),
                timeout: TimeInterval(timeout) + Self.startupAllowance
            )
        } catch let error as ToolError {
            throw ToolError("The sandbox couldn't run the code: \(Self.capped(error.message))")
        }
        let newFiles = Self.filePaths(in: workFolder).subtracting(filesBefore).sorted()
        guard !newFiles.isEmpty else { return Self.capped(output) }
        let savedFiles = try Self.saveToDownloads(newFiles, from: workFolder)
        return Self.capped(output) + "\n\n" + savedFiles
    }

    /// The `container` arguments that run `language`'s code file from `workFolder` under the time and resource limits.
    static func containerArguments(language: SandboxLanguage, workFolder: URL, timeoutSeconds: Int) -> [String] {
        [
            "run", "--rm", "--progress", "none",
            "--volume", "\(workFolder.path):\(containerWorkFolder)", "--workdir", containerWorkFolder,
            "--memory", memoryLimit, "--cpus", cpuLimit,
            language.image,
            "sh", "-c", runnerScript, "sandbox", String(timeoutSeconds), language.interpreter, language.codeFileName,
        ]
    }

    /// The last `outputLimit` characters of `output`, noting how much was cut.
    static func capped(_ output: String) -> String {
        guard output.count > outputLimit else { return output }
        return "[first \(output.count - outputLimit) characters truncated]\n" + output.suffix(outputLimit)
    }

    /// The path of the installed `container` CLI, once its system service answers.
    private static func readyCLI() async throws -> String {
        guard let cli = cliPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw ToolError("""
                The sandbox needs Apple's container tool, which runs on macOS 26 on Apple silicon. Download the signed \
                installer from github.com/apple/container/releases, then run `container system start` in Terminal.
                """)
        }
        do {
            _ = try await ProcessRunner.run(cli, ["system", "status"])
        } catch {
            throw ToolError("The container service isn't running. Run `container system start` in Terminal, then try again.")
        }
        return cli
    }

    /// Creates `workFolder` holding the code file and copies of `inputs`.
    private static func prepare(_ workFolder: URL, code: String, language: SandboxLanguage, inputs: [String]) throws {
        try FileManager.default.createDirectory(at: workFolder, withIntermediateDirectories: true)
        try Data(code.utf8).write(to: workFolder.appending(path: language.codeFileName))
        for path in inputs {
            let source = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            guard FileManager.default.fileExists(atPath: source.path) else {
                throw ToolError("Nothing exists at \(source.path). Use search_files to find it.")
            }
            let destination = workFolder.appending(path: source.lastPathComponent)
            guard !FileManager.default.fileExists(atPath: destination.path) else {
                throw ToolError("Two inputs are named \(source.lastPathComponent) (the code is \(language.codeFileName)). Pass files with different names.")
            }
            try FileManager.default.copyItem(at: source, to: destination)
        }
    }

    /// Paths of the regular files under `folder`, relative to it; symbolic links, and anything reached through one, are skipped, since the code could point them at the Mac's files.
    private static func filePaths(in folder: URL) -> Set<String> {
        let paths = (try? FileManager.default.subpathsOfDirectory(atPath: folder.path)) ?? []
        return Set(paths.filter { path in
            fileType(at: folder.appending(path: path)) == .typeRegular && isReachedThroughFolders(path, in: folder)
        })
    }

    /// Whether every folder on the way from `folder` to `relativePath` is a real folder rather than a link that could lead out of it.
    private static func isReachedThroughFolders(_ relativePath: String, in folder: URL) -> Bool {
        var current = folder
        for component in relativePath.split(separator: "/").dropLast() {
            current = current.appending(path: String(component))
            guard fileType(at: current) == .typeDirectory else { return false }
        }
        return true
    }

    /// The type of the item at `url` itself, not following a link.
    private static func fileType(at url: URL) -> FileAttributeType? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType
    }

    /// Copies `relativePaths` from `workFolder` into a new timestamped folder in Downloads and lists where they went.
    private static func saveToDownloads(_ relativePaths: [String], from workFolder: URL) throws -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let resultFolder = resultFolders.appending(path: formatter.string(from: .now))
        var savedPaths: [String] = []
        for relativePath in relativePaths {
            let destination = resultFolder.appending(path: relativePath)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: workFolder.appending(path: relativePath), to: destination)
            savedPaths.append(destination.path)
        }
        let listed = savedPaths.prefix(listedFileLimit).joined(separator: "\n")
        let more = savedPaths.count > listedFileLimit ? "\n…and \(savedPaths.count - listedFileLimit) more." : ""
        return "New files, saved to \(resultFolder.path):\n\(listed)\(more)"
    }
}
