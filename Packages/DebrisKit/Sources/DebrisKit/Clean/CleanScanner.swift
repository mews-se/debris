import Foundation

public actor CleanScanner {
    private let inventory: AppInventory
    private let classifier: Classifier
    private let protection: ProtectionRules
    private let rules: [CleanRule]

    static let installerExtensions: Set<String> = ["dmg", "pkg", "mpkg", "xip"]

    public init(inventory: AppInventory, rules: [CleanRule]? = nil, protection: ProtectionRules = .standard) {
        self.inventory = inventory
        self.classifier = Classifier(inventory: inventory, protection: protection)
        self.protection = protection
        self.rules = rules ?? CleanCatalog.standard()
    }

    public func scan(measureSizes: Bool = true,
                     progress: (@Sendable (ScanProgress) -> Void)? = nil) async -> [CleanGroup] {
        var groups: [CleanGroup] = []
        var claimed = Set<String>()
        // specific rules first, so a tool cache under ~/Library/Caches is not listed twice
        let ordered = rules.filter { $0.scope != .appOwned } + rules.filter { $0.scope == .appOwned }
        for (index, rule) in ordered.enumerated() {
            progress?(ScanProgress(phase: rule.title, completed: index, total: ordered.count))
            let items = resolve(rule).filter { !claimed.contains($0.url.path) }
            claimed.formUnion(items.map(\.url.path))
            if !items.isEmpty { groups.append(CleanGroup(rule: rule, items: items)) }
            await Task.yield()
        }
        groups.sort { lhs, rhs in
            let l = rules.firstIndex(of: lhs.rule) ?? 0
            let r = rules.firstIndex(of: rhs.rule) ?? 0
            return l < r
        }
        if measureSizes {
            let flat = groups.flatMap(\.items)
            let total = flat.count
            progress?(ScanProgress(phase: "Measuring sizes", completed: 0, total: total))
            let measured = await FileSizer.measure(flat) { done in
                progress?(ScanProgress(phase: "Measuring sizes", completed: done, total: total))
            }
            var cursor = 0
            for index in groups.indices {
                let count = groups[index].items.count
                groups[index].items = Array(measured[cursor..<cursor + count]).sorted { ($0.size ?? 0) > ($1.size ?? 0) }
                cursor += count
            }
        }
        return groups
    }

    private func resolve(_ rule: CleanRule) -> [LeftoverItem] {
        let fm = FileManager.default
        var items: [LeftoverItem] = []
        for root in rule.paths {
            let location = LeftoverLocation(kind: rule.kind, domain: .user, url: root)
            switch rule.scope {
            case .folder:
                guard hasContent(root) else { continue }
                items.append(item(at: root, location: location, rule: rule))
            case .children, .appOwned, .installers:
                guard let entries = try? fm.contentsOfDirectory(atPath: root.path) else { continue }
                for entry in entries.sorted() where !entry.hasPrefix(".") {
                    let url = root.appendingPathComponent(entry)
                    switch rule.scope {
                    case .installers:
                        guard Self.installerExtensions.contains(url.pathExtension.lowercased()) else { continue }
                    case .appOwned:
                        guard let owner = installedOwner(of: entry, in: location) else { continue }
                        items.append(item(at: url, location: location, rule: rule, owner: owner))
                        continue
                    default:
                        break
                    }
                    items.append(item(at: url, location: location, rule: rule))
                }
            case .unavailableSimulators:
                guard fm.fileExists(atPath: root.path) else { continue }
                for url in Simulators.unavailableDevices() {
                    items.append(item(at: url, location: location, rule: rule))
                }
            }
        }
        return items
    }

    /// The installed app that owns a cache or log folder, or nil when it is Apple's, shared
    /// SDK state, or a leftover of an app that is gone.
    private func installedOwner(of name: String, in location: LeftoverLocation) -> String? {
        let identifier = IdentifierParser.identifier(fromName: name)
        if name.lowercased().hasPrefix("com.apple.") { return nil }
        if protection.reason(forName: name, identifier: identifier, location: location) != nil { return nil }
        guard classifier.classify(name: name, identifier: identifier, location: location) == nil else { return nil }
        if let identifier, let related = inventory.relatedBundleID(to: identifier) { return related }
        return ""
    }

    private func item(at url: URL, location: LeftoverLocation, rule: CleanRule, owner: String? = nil) -> LeftoverItem {
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        let ownership: Ownership = (owner?.isEmpty == false) ? .installed(bundleID: owner!) : .unknown
        return LeftoverItem(url: url, location: location, identifier: IdentifierParser.identifier(fromName: url.lastPathComponent),
                            classification: Classification(ownership: ownership, confidence: .high, evidence: [rule.why]),
                            modified: modified)
    }

    private func hasContent(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return false }
        guard isDirectory.boolValue else { return true }
        return !((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).isEmpty
    }
}

enum Simulators {
    /// Device folders simctl reports as unavailable, which is what it says when the runtime is gone.
    static func unavailableDevices() -> [URL] {
        guard let json = try? Shell.run("/usr/bin/xcrun", ["simctl", "list", "devices", "-j"], timeout: 30),
              let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let runtimes = root["devices"] as? [String: [[String: Any]]]
        else { return [] }
        var urls: [URL] = []
        for devices in runtimes.values {
            for device in devices where (device["isAvailable"] as? Bool) == false {
                guard let dataPath = device["dataPath"] as? String else { continue }
                let folder = URL(fileURLWithPath: dataPath).deletingLastPathComponent()
                if FileManager.default.fileExists(atPath: folder.path) { urls.append(folder) }
            }
        }
        return urls.sorted { $0.path < $1.path }
    }
}
