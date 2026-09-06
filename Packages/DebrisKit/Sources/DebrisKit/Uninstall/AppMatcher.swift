import Foundation

/// Decides whether a file in one of the leftover locations belongs to one particular installed
/// app. Uses the same signals as the Classifier, turned around: instead of "does anyone own
/// this", it asks "does this app own it, and nobody else".
public struct AppMatcher: Sendable {
    public let app: InstalledApp
    let inventory: AppInventory
    let ownIDs: Set<String>
    let otherIDs: Set<String>
    let appName: String
    let nameWords: Set<String>
    let otherNames: [String]

    public init(app: InstalledApp, inventory: AppInventory) {
        self.app = app
        self.inventory = inventory
        let prefix = app.url.path + "/"
        let mainID = app.bundleID.lowercased()
        var own = Set<String>([mainID])
        var other = Set<String>()
        var embeddedElsewhere = Set<String>()
        var otherNames: [String] = []
        var otherWords = Set<String>()
        for candidate in inventory.apps {
            let id = candidate.bundleID.lowercased()
            if candidate.url.path.hasPrefix(prefix) || candidate.url == app.url {
                own.insert(id)
            } else if candidate.isTopLevel {
                other.insert(id)
                otherNames.append(Identifier.normalized(candidate.name))
                otherWords.formUnion(Self.productWords(of: id))
            } else {
                embeddedElsewhere.insert(id)
            }
        }
        // A helper bundled inside this app and inside another app (Microsoft Error Reporting,
        // Sparkle's updater) is shared state, not this app's.
        own.subtract(embeddedElsewhere.subtracting([mainID]))
        self.ownIDs = own
        self.otherIDs = other.subtracting(own)
        self.appName = Identifier.normalized(app.name)
        var words = Self.productWords(of: mainID)
        words.insert(Identifier.normalized(app.url.deletingPathExtension().lastPathComponent))
        words.remove("")
        self.nameWords = words.subtracting(otherWords)
        self.otherNames = otherNames
    }

    /// Identifier components after the vendor: "com.microsoft.Word" -> ["word"].
    static func productWords(of bundleID: String) -> Set<String> {
        let vendorCount = Identifier.vendor(of: bundleID).split(separator: ".").count
        let parts = Identifier.components(of: bundleID).dropFirst(vendorCount)
        return Set(parts.map(Identifier.normalized).filter { $0.count >= 4 })
    }

    /// The reason the file belongs to the app, or nil when it does not.
    public func reason(forName name: String, identifier: String?, location: LeftoverLocation) -> String? {
        if let identifier {
            let lower = identifier.lowercased()
            if let owner = related(lower, in: ownIDs, allowParentsOf: app.bundleID.lowercased()) {
                if let foreign = related(lower, in: otherIDs, allowParentsOf: nil), foreign.count > owner.count { return nil }
                return "Identifier matches \(owner)"
            }
            if related(lower, in: otherIDs, allowParentsOf: nil) != nil { return nil }
        }

        // A group counts only when no other installed app declares it too: Office apps share
        // UBF8T346G9.Office, so it is nobody's to remove until the last of them goes.
        let groupName = IdentifierParser.appGroupName(of: name).lowercased()
        if let declared = app.appGroups.first(where: { $0.lowercased() == name.lowercased() || IdentifierParser.appGroupName(of: $0).lowercased() == groupName }) {
            let owners = inventory.owners(ofAppGroup: declared)
            if owners.subtracting(ownIDs).isEmpty {
                return "App group declared only in this app's signature"
            }
            return nil
        }
        if let team = app.teamID, IdentifierParser.teamPrefix(of: name) == team {
            let rest = Identifier.normalized(IdentifierParser.stripContainerPrefixes(name))
            if rest == appName || nameWords.contains(where: { $0.count >= 4 && rest.contains($0) }) {
                return "Team \(team) container named after the app"
            }
        }

        if [.launchAgents, .launchDaemons].contains(location.kind) {
            let plist = location.url.appendingPathComponent(name)
            if let ids = LaunchdPlist.associatedBundleIDs(at: plist), ids.contains(where: { related($0.lowercased(), in: ownIDs, allowParentsOf: nil) != nil }) {
                return "Launch job for the app"
            }
            if let program = LaunchdPlist.program(at: plist), program.hasPrefix(app.url.path + "/") {
                return "Launch job runs a program inside the app"
            }
        }

        if identifier != nil { return nil }
        return plainNameReason(name)
    }

    private func plainNameReason(_ name: String) -> String? {
        var stem = (name as NSString).deletingPathExtension
        if stem.hasPrefix(".") { stem = String(stem.dropFirst()) }
        let normalized = Identifier.normalized(stem)
        guard normalized.count >= 4 else { return nil }

        if normalized == appName { return "Named after the app" }
        if nameWords.contains(normalized) { return "Named after the app's identifier" }
        if normalized.count >= 6, appName.hasPrefix(normalized) || normalized.hasPrefix(appName) {
            let ambiguous = otherNames.contains { $0.count >= 6 && $0 != appName && ($0.hasPrefix(normalized) || normalized.hasPrefix($0)) }
            return ambiguous ? nil : "Name matches the app"
        }
        if let owners = ProtectionRules.knownOwners[name], owners.contains(where: { appName.hasPrefix($0) || $0.hasPrefix(appName) }) {
            return "Known to belong to the app"
        }
        return nil
    }

    /// Exact match, a child of a known identifier, or (for identifiers with at least three
    /// components) a parent of the app's main identifier. Parents of embedded helpers do not
    /// count: com.microsoft.office is not Word just because Word embeds com.microsoft.office.x.
    private func related(_ identifier: String, in set: Set<String>, allowParentsOf parentTarget: String?) -> String? {
        if set.contains(identifier) { return identifier }
        let components = identifier.split(separator: ".").count
        for known in set {
            if identifier.hasPrefix(known), let next = identifier.dropFirst(known.count).first, "._-".contains(next) { return known }
            if components >= 3, known == parentTarget, known.hasPrefix(identifier + ".") { return known }
        }
        return nil
    }
}
