// ProcessRunner.swift
// MacGuard - Anti-Theft Alarm for macOS

import Foundation

enum ProcessRunner {
    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 30) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = FileHandle.nullDevice

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { finished in
                let message = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if finished.terminationReason == .exit && finished.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    let name = (executable as NSString).lastPathComponent
                    continuation.resume(throwing: NotifierError(
                        message: "\(name) exited \(finished.terminationStatus)\(message.isEmpty ? "" : ": \(message)")"))
                }
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if process.isRunning { process.terminate() }
            }
        }
    }

    /// User values arrive only as `argv`, never spliced into the source, so they can't inject script.
    static func osascript(_ lines: [String], arguments: [String]) async throws {
        let program = lines.flatMap { ["-e", $0] }
        try await run("/usr/bin/osascript", program + arguments)
    }
}
