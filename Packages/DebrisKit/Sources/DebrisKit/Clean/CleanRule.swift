import Foundation

/// One kind of removable junk: where it lives, what it is and why it is safe to move.
public struct CleanRule: Sendable, Identifiable, Hashable {
    public enum Category: String, Sendable, CaseIterable {
        case caches = "Caches"
        case logs = "Logs"
        case developer = "Developer"
        case packageManagers = "Package managers"
        case installers = "Installers"
    }

    public enum Scope: Sendable, Hashable {
        /// Each path is one item.
        case folder
        /// Every entry inside each path is one item.
        case children
        /// Entries inside each path that an installed app owns. Apple's own folders are left
        /// alone and entries of removed apps are left to the Leftovers scan.
        case appOwned
        /// Disk images and installer packages inside each path.
        case installers
        /// Simulator devices whose runtime is gone, found through simctl.
        case unavailableSimulators
    }

    public let id: String
    public let category: Category
    public let title: String
    public let what: String
    public let why: String
    public let paths: [URL]
    public let scope: Scope
    public let kind: LeftoverLocation.Kind
    public let selectedByDefault: Bool

    public init(id: String, category: Category, title: String, what: String, why: String,
                paths: [URL], scope: Scope, kind: LeftoverLocation.Kind, selectedByDefault: Bool = true) {
        self.id = id
        self.category = category
        self.title = title
        self.what = what
        self.why = why
        self.paths = paths
        self.scope = scope
        self.kind = kind
        self.selectedByDefault = selectedByDefault
    }
}

public struct CleanGroup: Sendable, Identifiable {
    public let rule: CleanRule
    public var items: [LeftoverItem]

    public init(rule: CleanRule, items: [LeftoverItem]) {
        self.rule = rule
        self.items = items
    }

    public var id: String { rule.id }
    public var totalSize: Int64 { items.reduce(0) { $0 + ($1.size ?? 0) } }
}
