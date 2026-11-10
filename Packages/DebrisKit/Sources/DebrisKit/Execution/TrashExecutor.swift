import Foundation

public struct RemovalResult: Sendable, Identifiable {
    public enum Outcome: Sendable {
        case trashed(URL)
        case failed(String)
    }

    public let url: URL
    public let outcome: Outcome
    public var size: Int64?

    public init(url: URL, outcome: Outcome, size: Int64? = nil) {
        self.url = url
        self.outcome = outcome
        self.size = size
    }

    public var id: String { url.path }
    public var succeeded: Bool { if case .trashed = outcome { true } else { false } }
}

extension Array where Element == RemovalResult {
    /// Carries the measured sizes of the removed items over to their results.
    public func sized(from items: [LeftoverItem]) -> [RemovalResult] {
        let sizes = Dictionary(items.map { ($0.url.path, $0.size) }, uniquingKeysWith: { first, _ in first })
        return map { result in
            var result = result
            result.size = sizes[result.url.path] ?? nil
            return result
        }
    }
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
