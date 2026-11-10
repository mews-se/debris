import Foundation

public enum FullDiskAccess {
    public static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

    /// Places only Full Disk Access can read. More than one, because they come and go: the
    /// per-user TCC database is gone on macOS 27, and an account that never opened Safari or
    /// Mail has no folder for them.
    public static func candidates(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        [
            URL(fileURLWithPath: "/Library/Application Support/com.apple.TCC/TCC.db"),
            home.appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db"),
            home.appendingPathComponent("Library/Safari"),
            home.appendingPathComponent("Library/Mail"),
        ]
    }

    public static func isGranted(probes: [URL] = candidates()) -> Bool {
        probes.contains(where: canRead)
    }

    static func canRead(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return false }
        if isDirectory.boolValue {
            return (try? FileManager.default.contentsOfDirectory(atPath: url.path)) != nil
        }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        try? handle.close()
        return true
    }
}
