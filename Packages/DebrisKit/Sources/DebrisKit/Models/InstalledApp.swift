import Foundation

public struct InstalledApp: Sendable, Hashable, Identifiable {
    public enum Source: Sendable, Hashable {
        case applications
        case userApplications
        case system
        case embedded
        case homebrewCask(String)
        case other
    }

    public let bundleID: String
    public let name: String
    public let url: URL
    public let version: String?
    public let teamID: String?
    public let appGroups: [String]
    public let source: Source

    public init(bundleID: String, name: String, url: URL, version: String? = nil,
                teamID: String? = nil, appGroups: [String] = [], source: Source = .other) {
        self.bundleID = bundleID
        self.name = name
        self.url = url
        self.version = version
        self.teamID = teamID
        self.appGroups = appGroups
        self.source = source
    }

    public var id: String { url.path }
    public var isTopLevel: Bool { source != .embedded }
    public var vendor: String { Identifier.vendor(of: bundleID) }
}
