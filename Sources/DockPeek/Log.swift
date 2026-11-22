import Foundation

/// Tiny file logger: ~/Library/Logs/DockPeek.log
enum Log {
    private static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/DockPeek.log")
    private static let formatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f
    }()

    static func reset() { try? "".write(to: url, atomically: true, encoding: .utf8) }

    static func write(_ message: String) {
        let line = "\(formatter.string(from: Date()))  \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile(); handle.write(data); try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}
