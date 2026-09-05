import Foundation

public struct AppInventory: Sendable {
    public let apps: [InstalledApp]
    public let homebrewFormulae: Set<String>
    public let scannedAt: Date

    let bundleIDs: Set<String>
    let names: Set<String>
    let vendors: Set<String>
    let vendorWords: Set<String>
    let teamIDs: Set<String>
    let appGroups: Set<String>
    let bundleWords: Set<String>
    let byBundleID: [String: InstalledApp]

    public init(apps: [InstalledApp], homebrewFormulae: Set<String> = [], scannedAt: Date = .now) {
        self.apps = apps
        self.homebrewFormulae = Set(homebrewFormulae.map { $0.lowercased() })
        self.scannedAt = scannedAt

        var ids = Set<String>()
        var names = Set<String>()
        var vendors = Set<String>()
        var vendorWords = Set<String>()
        var teams = Set<String>()
        var groups = Set<String>()
        var words = Set<String>()
        var byID: [String: InstalledApp] = [:]
        for app in apps {
            let id = app.bundleID.lowercased()
            ids.insert(id)
            for word in IdentifierParser.nameParts(of: id) { words.insert(word) }
            vendors.insert(app.vendor)
            if let word = app.vendor.split(separator: ".").dropFirst().first, word.count >= 5 { vendorWords.insert(String(word)) }
            names.insert(Identifier.normalized(app.name))
            names.insert(Identifier.normalized(app.url.deletingPathExtension().lastPathComponent))
            if let team = app.teamID { teams.insert(team) }
            for group in app.appGroups { groups.insert(group.lowercased()) }
            if let existing = byID[id] {
                if !existing.isTopLevel && app.isTopLevel { byID[id] = app }
            } else {
                byID[id] = app
            }
        }
        for formula in homebrewFormulae { names.insert(Identifier.normalized(formula)) }
        names.remove("")
        self.bundleIDs = ids
        self.names = names
        self.vendors = vendors
        self.vendorWords = vendorWords
        self.teamIDs = teams
        self.appGroups = groups
        self.bundleWords = words
        self.byBundleID = byID
    }

    public static let empty = AppInventory(apps: [])

    public var topLevelApps: [InstalledApp] {
        apps.filter(\.isTopLevel).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func app(for bundleID: String) -> InstalledApp? {
        byBundleID[bundleID.lowercased()]
    }

    public func contains(bundleID: String) -> Bool {
        bundleIDs.contains(bundleID.lowercased())
    }

    /// Exact match, or a parent/child relation such as com.foo.App vs com.foo.App.Helper.
    public func relatedBundleID(to identifier: String) -> String? {
        let id = identifier.lowercased()
        if bundleIDs.contains(id) { return id }
        for known in bundleIDs {
            if known.hasPrefix(id + ".") { return known }
            if id.hasPrefix(known), let next = id.dropFirst(known.count).first, "._-".contains(next) { return known }
        }
        return nil
    }

    /// "coconut-flavour" for an installed com.coconut-flavour.coconutBattery.
    public func vendorWordIsInstalled(_ word: String) -> Bool {
        vendorWords.contains(word.lowercased())
    }

    public func vendorIsInstalled(_ vendor: String) -> Bool {
        vendors.contains(vendor.lowercased())
    }

    public func nameIsInstalled(_ normalizedName: String) -> Bool {
        !normalizedName.isEmpty && names.contains(normalizedName)
    }

    /// A known name at least `minimumLength` characters long contained in the text, or vice versa.
    public func fuzzyNameMatch(_ normalizedName: String, minimumLength: Int = 5) -> String? {
        guard normalizedName.count >= minimumLength else { return nil }
        for known in names where known.count >= minimumLength {
            if normalizedName.contains(known) || known.contains(normalizedName) { return known }
        }
        return nil
    }

    /// A word from an installed bundle identifier (at least four characters) contained in the text.
    public func bundleWordMatch(_ normalizedName: String) -> String? {
        for word in bundleWords where word.count >= 4 && normalizedName.contains(word) { return word }
        return nil
    }

    /// The name is a word of an installed bundle identifier, e.g. "Codex" for com.openai.codex.
    public func bundleWordIsInstalled(_ normalizedName: String) -> Bool {
        normalizedName.count >= 4 && bundleWords.contains(normalizedName)
    }

    /// One name starts with the other and both are long enough to mean something:
    /// "Raspberry Pi" against "Raspberry Pi Imager", "TorBrowser-Data" against "Tor Browser".
    public func prefixNameMatch(_ normalizedName: String, minimumLength: Int = 6) -> String? {
        guard normalizedName.count >= minimumLength else { return nil }
        for known in names where known.count >= minimumLength {
            if normalizedName.hasPrefix(known) || known.hasPrefix(normalizedName) { return known }
        }
        return nil
    }

    public func teamIsInstalled(_ teamID: String) -> Bool { teamIDs.contains(teamID) }
    public func appGroupIsInstalled(_ group: String) -> Bool { appGroups.contains(group.lowercased()) }
}
