import Foundation

/// Runs command-line programs for tools, returning their combined output.
enum ProcessRunner {
    /// Most output bytes kept; beyond this only the end is kept, so a program that floods output can't exhaust memory.
    private static let outputByteLimit = 8_000_000
    /// Put before output whose start was dropped.
    private static let droppedOutputNote = "[earlier output dropped]\n"

    /// Runs `executable` with `arguments`, feeding `input` on stdin; throws with the output when it exits non-zero or times out.
    static func run(
        _ executable: String,
        _ arguments: [String] = [],
        input: String? = nil,
        timeout: TimeInterval = 30
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let output = Pipe()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.standardOutput = output
                process.standardError = output
                let stdin = Pipe()
                process.standardInput = stdin
                do {
                    try process.run()
                } catch {
                    return continuation.resume(throwing: ToolError("Couldn't start \(executable): \(error.localizedDescription)"))
                }
                let deadline = DispatchWorkItem { process.terminate() }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
                if let input { try? stdin.fileHandleForWriting.write(contentsOf: Data(input.utf8)) }
                try? stdin.fileHandleForWriting.close()
                let data = lastOutput(from: output.fileHandleForReading)
                process.waitUntilExit()
                deadline.cancel()
                let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                if process.terminationReason == .uncaughtSignal {
                    continuation.resume(throwing: ToolError("Stopped after \(Int(timeout)) seconds. Output so far: \(text)"))
                } else if process.terminationStatus != 0 {
                    continuation.resume(throwing: ToolError(text.isEmpty ? "Exited with status \(process.terminationStatus)." : text))
                } else {
                    continuation.resume(returning: text)
                }
            }
        }
    }

    /// Everything `handle` yields until the program closes it, keeping only the last `outputByteLimit` bytes.
    private static func lastOutput(from handle: FileHandle) -> Data {
        var data = Data()
        var droppedOutput = false
        while let chunk = try? handle.read(upToCount: 65_536), !chunk.isEmpty {
            data.append(chunk)
            if data.count > 2 * outputByteLimit {
                data = Data(data.suffix(outputByteLimit))
                droppedOutput = true
            }
        }
        if data.count > outputByteLimit {
            data = Data(data.suffix(outputByteLimit))
            droppedOutput = true
        }
        return droppedOutput ? Data(droppedOutputNote.utf8) + data : data
    }
}
