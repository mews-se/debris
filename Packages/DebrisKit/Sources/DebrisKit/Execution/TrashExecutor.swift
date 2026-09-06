import Foundation

public struct RemovalResult: Sendable, Identifiable {
    public enum Outcome: Sendable {
        case trashed(URL)
        case failed(String)
    }

    public let url: URL
    public let outcome: Outcome

    public init(url: URL, outcome: Outcome) {
        self.url = url
        self.outcome = outcome
    }

    public var id: String { url.path }
    public var succeeded: Bool { if case .trashed = outcome { true } else { false } }
}

/// Moves the user's own files to the Trash. Files owned by the system go through AdminRemover.
public enum TrashExecutor {
    public static func trash(_ urls: [URL]) -> [RemovalResult] {
        let fm = FileManager.default
        return urls.map { url in
            unloadIfLaunchAgent(url)
            var trashed: NSURL?
            do {
                try fm.trashItem(at: url, resultingItemURL: &trashed)
            } catch {
                // a locked file cannot be renamed; clear the flag and try once more
                guard (try? fm.setAttributes([.immutable: false], ofItemAtPath: url.path)) != nil,
                      (try? fm.trashItem(at: url, resultingItemURL: &trashed)) != nil
                else { return RemovalResult(url: url, outcome: .failed(error.localizedDescription)) }
            }
            return RemovalResult(url: url, outcome: .trashed((trashed as URL?) ?? url))
        }
    }

    /// A launch agent keeps running after its plist is gone unless launchd is told.
    static func unloadIfLaunchAgent(_ url: URL) {
        guard url.pathExtension == "plist",
              url.deletingLastPathComponent().lastPathComponent == "LaunchAgents",
              url.path.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.path)
        else { return }
        _ = try? Shell.run("/bin/launchctl", ["bootout", "gui/\(getuid())", url.path], timeout: 10)
    }
}
