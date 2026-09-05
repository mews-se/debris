import Foundation

public enum FullDiskAccess {
    public static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

    /// Reading the per-user TCC database only succeeds with Full Disk Access.
    public static func isGranted(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        let probe = home.appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db")
        guard let handle = try? FileHandle(forReadingFrom: probe) else { return false }
        try? handle.close()
        return true
    }
}
