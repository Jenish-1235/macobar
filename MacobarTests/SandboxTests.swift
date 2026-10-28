import Foundation
import Testing

/// Verifies the `container run` command line built for sandboxed code and how its output is capped.
struct SandboxTests {
    /// A work folder whose path contains a space, as Application Support does.
    private let workFolder = URL(fileURLWithPath: "/Users/me/Library/Application Support/macobar/sandbox/run")

    @Test("Each language runs its code file with its own image and interpreter")
    func imagePerLanguage() {
        let expected: [SandboxLanguage: [String]] = [
            .python: ["python:3.13-slim", "python3", "main.py"],
            .node: ["node:22-slim", "node", "main.js"],
            .shell: ["alpine:3", "sh", "main.sh"],
        ]
        for (language, parts) in expected {
            let arguments = RunInSandboxTool.containerArguments(language: language, workFolder: workFolder, timeoutSeconds: 120)
            #expect(arguments.contains(parts[0]))
            #expect(Array(arguments.suffix(2)) == [parts[1], parts[2]])
        }
    }

    @Test("The run mounts the work folder at /work, starts there, and limits memory and CPUs")
    func mountAndLimits() throws {
        let arguments = RunInSandboxTool.containerArguments(language: .python, workFolder: workFolder, timeoutSeconds: 120)
        let imageIndex = try #require(arguments.firstIndex(of: "python:3.13-slim"))
        #expect(Array(arguments[..<imageIndex]) == [
            "run", "--rm", "--progress", "none",
            "--volume", "/Users/me/Library/Application Support/macobar/sandbox/run:/work", "--workdir", "/work",
            "--memory", "2g", "--cpus", "2",
        ])
    }

    @Test("The code runs under the time limit through a fixed script that takes everything else as arguments")
    func timeLimit() throws {
        let arguments = RunInSandboxTool.containerArguments(language: .node, workFolder: workFolder, timeoutSeconds: 45)
        let imageIndex = try #require(arguments.firstIndex(of: "node:22-slim"))
        let command = Array(arguments[(imageIndex + 1)...])
        #expect(command.count == 7)
        #expect(Array(command.prefix(2)) == ["sh", "-c"])
        #expect(command[2].hasPrefix(#"timeout "$1" "$2" "$3""#))
        #expect(Array(command.suffix(4)) == ["sandbox", "45", "node", "main.js"])
    }

    @Test("Output within the limit is returned unchanged")
    func shortOutput() {
        let output = String(repeating: "a", count: RunInSandboxTool.outputLimit)
        #expect(RunInSandboxTool.capped(output) == output)
    }

    @Test("Long output keeps its last characters and says how many were cut")
    func longOutput() {
        let output = String(repeating: "a", count: 10) + String(repeating: "b", count: RunInSandboxTool.outputLimit)
        #expect(RunInSandboxTool.capped(output) == "[first 10 characters truncated]\n" + String(repeating: "b", count: RunInSandboxTool.outputLimit))
    }
}
