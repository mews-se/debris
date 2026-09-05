import Foundation

public enum Ownership: Sendable, Hashable {
    case installed(bundleID: String)
    case vendor(String)
    case name(String)
    case apple
    case unknown

    public var isLeftover: Bool {
        switch self {
        case .installed, .apple: false
        case .vendor, .name, .unknown: true
        }
    }
}

public enum Confidence: Int, Sendable, Comparable, CaseIterable {
    case low = 0
    case medium = 1
    case high = 2

    public static func < (lhs: Confidence, rhs: Confidence) -> Bool { lhs.rawValue < rhs.rawValue }

    public var title: String {
        switch self {
        case .high: "Likely leftover"
        case .medium: "Possibly leftover"
        case .low: "Unclear"
        }
    }
}

public struct Classification: Sendable, Hashable {
    public var ownership: Ownership
    public var confidence: Confidence
    public var evidence: [String]

    public init(ownership: Ownership, confidence: Confidence, evidence: [String] = []) {
        self.ownership = ownership
        self.confidence = confidence
        self.evidence = evidence
    }
}

public struct LeftoverItem: Sendable, Hashable, Identifiable {
    public let url: URL
    public let location: LeftoverLocation
    public let identifier: String?
    public let classification: Classification
    public let modified: Date?
    public var size: Int64?

    public init(url: URL, location: LeftoverLocation, identifier: String?,
                classification: Classification, modified: Date?, size: Int64? = nil) {
        self.url = url
        self.location = location
        self.identifier = identifier
        self.classification = classification
        self.modified = modified
        self.size = size
    }

    public var id: String { url.path }
    public var name: String { url.lastPathComponent }
    public var requiresAdmin: Bool { location.domain == .system }
    public var groupKey: String { Grouping.key(identifier: identifier, name: name) }
}

public struct GhostApp: Sendable, Identifiable {
    public let key: String
    public let title: String
    public var items: [LeftoverItem]

    public init(key: String, title: String, items: [LeftoverItem]) {
        self.key = key
        self.title = title
        self.items = items
    }

    public var id: String { key }
    public var totalSize: Int64 { items.reduce(0) { $0 + ($1.size ?? 0) } }
    public var newestChange: Date? { items.compactMap(\.modified).max() }
    public var confidence: Confidence { items.map(\.classification.confidence).max() ?? .low }
    public var needsAdmin: Bool { items.contains { $0.requiresAdmin } }
}

public struct ScanProgress: Sendable {
    public var phase: String
    public var completed: Int
    public var total: Int

    public init(phase: String, completed: Int = 0, total: Int = 0) {
        self.phase = phase
        self.completed = completed
        self.total = total
    }

    public var fraction: Double? { total > 0 ? Double(completed) / Double(total) : nil }
}
