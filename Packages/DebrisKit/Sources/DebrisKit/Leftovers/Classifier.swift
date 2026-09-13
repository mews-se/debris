import Foundation

public struct Classifier: Sendable {
    public let inventory: AppInventory
    public let protection: ProtectionRules

    public init(inventory: AppInventory, protection: ProtectionRules = .standard) {
        self.inventory = inventory
        self.protection = protection
    }

    /// nil means the item is protected or belongs to an installed app and is not a leftover.
    public func classify(name: String, identifier: String?, location: LeftoverLocation) -> Classification? {
        if protection.reason(forName: name, identifier: identifier, location: location) != nil { return nil }

        if let team = IdentifierParser.teamPrefix(of: name), inventory.teamIsInstalled(team) { return nil }
        if inventory.appGroupIsInstalled(IdentifierParser.appGroupName(of: name)) { return nil }
        if [.launchAgents, .launchDaemons].contains(location.kind), let associated = LaunchdPlist.associatedBundleIDs(at: location.url.appendingPathComponent(name)) {
            for bundleID in associated where inventory.relatedBundleID(to: bundleID) != nil { return nil }
        }

        if name.hasPrefix("homebrew.mxcl."), name.hasSuffix(".plist") {
            let formula = String(name.dropFirst("homebrew.mxcl.".count).dropLast(".plist".count))
            if inventory.nameIsInstalled(Identifier.normalized(formula)) { return nil }
            return Classification(ownership: .unknown, confidence: .high,
                                  evidence: ["Homebrew service for \(formula), which is no longer installed"])
        }

        if let identifier {
            return classify(identifier: identifier, name: name, location: location)
        }
        return classify(plainName: name, location: location)
    }

    private func classify(identifier: String, name: String, location: LeftoverLocation) -> Classification? {
        let lower = identifier.lowercased()
        if lower.hasPrefix("com.apple.") { return nil }
        if inventory.relatedBundleID(to: identifier) != nil { return nil }
        if inventory.appGroupIsInstalled(identifier) { return nil }

        // Qt apps write com.vendor.App Name.plist: the app's own name outranks a vendor match
        let parts = IdentifierParser.nameParts(of: identifier)
        if parts.contains(where: { $0.count >= 6 && inventory.appNameIsInstalled($0) }) { return nil }

        let vendor = Identifier.vendor(of: identifier)
        if inventory.vendorIsInstalled(vendor) {
            return Classification(ownership: .vendor(vendor), confidence: .medium,
                                  evidence: ["No app with this identifier, but \(vendor) still has apps installed"])
        }
        for part in parts where inventory.nameIsInstalled(part) {
            return Classification(ownership: .name(part), confidence: .low,
                                  evidence: ["\"\(part)\" matches the name of an installed app or Homebrew package"])
        }
        return Classification(ownership: .unknown, confidence: .high,
                              evidence: ["No installed app, helper or Homebrew package matches \(identifier)"])
    }

    private func classify(plainName name: String, location: LeftoverLocation) -> Classification? {
        if IdentifierParser.isUUIDName(name) {
            return Classification(ownership: .unknown, confidence: .low,
                                  evidence: ["Container named by UUID; its owner cannot be read without Full Disk Access"])
        }
        let normalized = Identifier.normalized(name)
        if normalized.isEmpty { return nil }

        if location.kind == .dotfiles || location.isDotfileArea {
            let owners = ProtectionRules.dotfileOwners[name] ?? []
            for owner in owners where inventory.nameIsInstalled(owner) { return nil }
            let stripped = name.hasPrefix(".") ? Identifier.normalized(String(name.dropFirst())) : normalized
            if inventory.nameIsInstalled(stripped) || inventory.bundleWordIsInstalled(stripped) || inventory.prefixNameMatch(stripped) != nil { return nil }
            if inventory.commandIsInstalled(stripped) { return nil }
            if let match = inventory.fuzzyNameMatch(stripped) {
                return Classification(ownership: .name(match), confidence: .low,
                                      evidence: ["Name resembles \(match), which is installed"])
            }
            let evidence = owners.isEmpty
                ? ["No installed app, command-line tool or Homebrew package matches this name"]
                : ["Belongs to \(owners.joined(separator: " or ")), which is not installed"]
            return Classification(ownership: .unknown, confidence: owners.isEmpty ? .medium : .high, evidence: evidence)
        }

        let stem = (name as NSString).deletingPathExtension
        let normalizedStem = Identifier.normalized(stem)
        if inventory.nameIsInstalled(normalized) || inventory.nameIsInstalled(normalizedStem) { return nil }
        if inventory.bundleWordIsInstalled(normalizedStem) || inventory.prefixNameMatch(normalizedStem) != nil { return nil }
        if inventory.commandIsInstalled(normalizedStem) { return nil }
        let stripped = IdentifierParser.stripContainerPrefixes(name)
        if let firstWord = stripped.split(separator: ".").first, inventory.vendorWordIsInstalled(String(firstWord)) {
            return Classification(ownership: .vendor(String(firstWord)), confidence: .medium,
                                  evidence: ["Not a current identifier, but \(firstWord) still has apps installed"])
        }
        let owners = ProtectionRules.knownOwners[name] ?? []
        for owner in owners where inventory.nameIsInstalled(owner) || inventory.fuzzyNameMatch(owner) != nil { return nil }
        if !owners.isEmpty {
            return Classification(ownership: .unknown, confidence: .high,
                                  evidence: ["Belongs to \(owners.first!), which is not installed"])
        }
        if let match = inventory.fuzzyNameMatch(normalizedStem) ?? inventory.bundleWordMatch(normalizedStem) {
            return Classification(ownership: .name(match), confidence: .low,
                                  evidence: ["Name resembles \(match), which is installed"])
        }
        let looksLikeDaemon = stem.range(of: #"^[a-z_]+(d|agent)$"#, options: .regularExpression) != nil
        if looksLikeDaemon {
            return Classification(ownership: .unknown, confidence: .low,
                                  evidence: ["Looks like a system daemon name"])
        }
        if location.kind == .preferences || location.kind == .savedState || location.kind == .httpStorages {
            return Classification(ownership: .unknown, confidence: .low,
                                  evidence: ["Not a bundle identifier; macOS itself writes many files like this"])
        }
        return Classification(ownership: .unknown, confidence: .high,
                              evidence: ["No installed app, command-line tool or Homebrew package matches this name"])
    }
}
