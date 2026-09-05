import Foundation

public struct RemovalResult: Sendable, Identifiable {
    public enum Outcome: Sendable {
        case trashed(URL)
        case failed(String)
    }

    public let url: URL
    public let outcome: Outcome

    public var id: String { url.path }
    public var succeeded: Bool { if case .trashed = outcome { true } else { false } }
}

public enum TrashExecutor {
    public static func trash(_ urls: [URL]) -> [RemovalResult] {
        let fm = FileManager.default
        return urls.map { url in
            var trashed: NSURL?
            do {
                try fm.trashItem(at: url, resultingItemURL: &trashed)
                return RemovalResult(url: url, outcome: .trashed((trashed as URL?) ?? url))
            } catch {
                return RemovalResult(url: url, outcome: .failed(error.localizedDescription))
            }
        }
    }
}
