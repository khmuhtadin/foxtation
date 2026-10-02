import Foundation

struct ProcessOutput {
    var status: Int32
    var stdout: String
    var stderr: String
    var seconds: Double

    var combined: String { stderr.isEmpty ? stdout : stderr }
}

/// Runs a child process, draining both pipes as data arrives so a chatty
/// binary can never fill a pipe buffer and deadlock.
enum ProcessRunner {

    static func run(executable: String,
                    arguments: [String],
                    environment: [String: String]? = nil,
                    timeout: TimeInterval = 1800,
                    onLine: ((String) -> Void)? = nil) async throws -> ProcessOutput {

        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.standardInput = FileHandle.nullDevice
                if let environment {
                    process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
                }

                let outPipe = Pipe(), errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe

                let lock = NSLock()
                var outData = Data(), errData = Data()

                func makeHandler(_ sink: @escaping (Data) -> Void, emit: Bool) -> (FileHandle) -> Void {
                    var buffer = Data()
                    return { handle in
                        let chunk = handle.availableData
                        guard !chunk.isEmpty else { return }
                        sink(chunk)
                        guard emit, let onLine else { return }
                        buffer.append(chunk)
                        while let index = buffer.firstIndex(of: 0x0A) {
                            let lineData = buffer[buffer.startIndex..<index]
                            buffer.removeSubrange(buffer.startIndex...index)
                            if let line = String(data: lineData, encoding: .utf8) {
                                DispatchQueue.main.async { onLine(line) }
                            }
                        }
                    }
                }

                outPipe.fileHandleForReading.readabilityHandler = makeHandler({ chunk in
                    lock.lock(); outData.append(chunk); lock.unlock()
                }, emit: false)

                errPipe.fileHandleForReading.readabilityHandler = makeHandler({ chunk in
                    lock.lock(); errData.append(chunk); lock.unlock()
                }, emit: true)

                let started = Date()
                do {
                    try process.run()
                } catch {
                    outPipe.fileHandleForReading.readabilityHandler = nil
                    errPipe.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: error)
                    return
                }

                let deadline = Date().addingTimeInterval(timeout)
                while process.isRunning && Date() < deadline {
                    usleep(60_000)
                }
                if process.isRunning { process.terminate() }

                process.waitUntilExit()
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                lock.lock()
                outData.append(outPipe.fileHandleForReading.readDataToEndOfFile())
                errData.append(errPipe.fileHandleForReading.readDataToEndOfFile())
                let out = outData, err = errData
                lock.unlock()

                continuation.resume(returning: ProcessOutput(
                    status: process.terminationStatus,
                    stdout: String(data: out, encoding: .utf8) ?? "",
                    stderr: String(data: err, encoding: .utf8) ?? "",
                    seconds: Date().timeIntervalSince(started)
                ))
            }
        }
    }

    /// Locates an executable by absolute path first, then along the user's PATH.
    static func locate(_ name: String, extra: [String] = []) -> String? {
        for candidate in extra where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":").map(String.init)
            + ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        for directory in paths {
            let candidate = directory + "/" + name
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }
}
