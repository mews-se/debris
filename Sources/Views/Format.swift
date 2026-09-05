import Foundation

@MainActor
enum Format {
    static let bytes: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    static func size(_ value: Int64?) -> String {
        guard let value else { return "" }
        return bytes.string(fromByteCount: value)
    }

    static func date(_ date: Date?) -> String {
        guard let date else { return "" }
        return date.formatted(.dateTime.year().month(.abbreviated).day())
    }

    static func homeRelative(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.deletingLastPathComponent().path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
