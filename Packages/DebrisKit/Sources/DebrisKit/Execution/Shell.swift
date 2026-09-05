import Foundation

enum Shell {
    struct Failure: Error { let status: Int32; let output: String }

    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 30) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        deadline.cancel()
        let output = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else { throw Failure(status: process.terminationStatus, output: output) }
        return output
    }
}
