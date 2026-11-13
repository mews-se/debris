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
            case .simulatorRuntimes:
                guard fm.fileExists(atPath: root.path), let images = Simulators.runtimeImagesJSON(),
                      let runtimes = Simulators.runtimesJSON() else { continue }
                for runtime in Simulators.olderRuntimes(images: images, runtimes: runtimes) {
                    items.append(runtime.item(location: location))
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

public enum Simulators {
    struct Runtime: Equatable {
        let id: String
        let platform: String
        let version: String
        let build: String
        let path: String
        let size: Int64
        let lastUsed: Date?
        var coveredBy: [String] = []

        func item(location: LeftoverLocation) -> LeftoverItem {
            let used = lastUsed.map { "Last used \($0.formatted(date: .abbreviated, time: .omitted))" }
                ?? "simctl has no record of it being used"
            let newer = coveredBy.count < 2 ? coveredBy.joined()
                : coveredBy.dropLast().joined(separator: ", ") + " or " + coveredBy.last!
            return LeftoverItem(url: URL(fileURLWithPath: path), location: location, identifier: nil,
                                classification: Classification(ownership: .unknown, confidence: .high,
                                                               evidence: ["Every device it simulates also runs on \(newer)", used]),
                                modified: lastUsed, size: size, displayName: "\(platform) \(version) (\(build))",
                                removal: .simulatorRuntime(id: id))
        }
    }

    /// A runtime as simctl list runtimes reports it, with the deletable images behind it.
    private struct Installed {
        let identifier: String
        let name: String
        let platform: String
        let version: String
        let build: String
        let bundlePath: String
        let available: Bool
        let deviceTypes: Set<String>
        var images: [Runtime] = []

        var title: String { "\(name) (\(build))" }

        func isOlder(than other: Installed) -> Bool {
            let version = version.compare(other.version, options: .numeric)
            if version != .orderedSame { return version == .orderedAscending }
            let build = build.compare(other.build, options: .numeric)
            if build != .orderedSame { return build == .orderedAscending }
            return bundlePath < other.bundlePath
        }
    }

    static func runtimeImagesJSON() -> Data? {
        (try? Shell.run("/usr/bin/xcrun", ["simctl", "runtime", "list", "-j"], timeout: 30))?.data(using: .utf8)
    }

    static func runtimesJSON() -> Data? {
        (try? Shell.run("/usr/bin/xcrun", ["simctl", "list", "-j", "runtimes"], timeout: 30))?.data(using: .utf8)
    }

    /// Deletable runtime images whose device types all run on a newer runtime that stays, oldest first.
    /// `images` is simctl runtime list, `runtimes` is simctl list runtimes, which knows the device types.
    /// A device-specific build only covers its own devices, so it never makes a general runtime look old.
    static func olderRuntimes(images: Data, runtimes: Data) -> [Runtime] {
        guard let imageRoot = try? JSONSerialization.jsonObject(with: images) as? [String: [String: Any]],
              let runtimeRoot = try? JSONSerialization.jsonObject(with: runtimes) as? [String: Any],
              let listed = runtimeRoot["runtimes"] as? [[String: Any]]
        else { return [] }

        var installed: [Installed] = listed.compactMap { entry in
            guard let identifier = entry["identifier"] as? String,
                  let name = entry["name"] as? String,
                  let version = entry["version"] as? String,
                  let build = entry["buildversion"] as? String
            else { return nil }
            let types = (entry["supportedDeviceTypes"] as? [[String: Any]] ?? []).compactMap { $0["identifier"] as? String }
            return Installed(identifier: identifier, name: name, platform: entry["platform"] as? String ?? "",
                             version: version, build: build, bundlePath: entry["bundlePath"] as? String ?? "",
                             available: (entry["isAvailable"] as? Bool) == true, deviceTypes: Set(types))
        }

        let dates = ISO8601DateFormatter()
        for image in imageRoot.values where (image["deletable"] as? Bool) == true {
            guard let id = image["identifier"] as? String,
                  let version = image["version"] as? String,
                  let path = image["path"] as? String
            else { continue }
            let build = image["build"] as? String ?? ""
            let bundlePath = image["runtimeBundlePath"] as? String ?? ""
            let runtimeID = image["runtimeIdentifier"] as? String ?? ""
            // an image simctl list runtimes does not report has unknown device types and is never listed
            guard let index = installed.indices.first(where: {
                (!bundlePath.isEmpty && installed[$0].bundlePath == bundlePath)
                    || (installed[$0].identifier == runtimeID && installed[$0].build == build)
            }) else { continue }
            installed[index].images.append(Runtime(id: id, platform: platformName(image["platformIdentifier"] as? String ?? ""),
                                                   version: version, build: build, path: path,
                                                   size: (image["sizeBytes"] as? NSNumber)?.int64Value ?? 0,
                                                   lastUsed: (image["lastUsedAt"] as? String).flatMap(dates.date(from:))))
        }

        var older: [Runtime] = []
        for platform in Dictionary(grouping: installed, by: \.platform).values {
            var staying: [Installed] = []
            for runtime in platform.sorted(by: { $1.isOlder(than: $0) }) {
                let covering = staying.filter { !$0.deviceTypes.isDisjoint(with: runtime.deviceTypes) }
                let covered = covering.reduce(into: Set<String>()) { $0.formUnion($1.deviceTypes) }
                if !runtime.images.isEmpty, !runtime.deviceTypes.isEmpty, runtime.deviceTypes.isSubset(of: covered) {
                    older += runtime.images.map { image in
                        var image = image
                        image.coveredBy = covering.reversed().map(\.title)
                        return image
                    }
                } else if runtime.available {
                    staying.append(runtime)
                }
            }
        }
        return older.sorted {
            if $0.platform != $1.platform { return $0.platform < $1.platform }
            let version = $0.version.compare($1.version, options: .numeric)
            if version != .orderedSame { return version == .orderedAscending }
            return $0.build.compare($1.build, options: .numeric) == .orderedAscending
        }
    }

    static func platformName(_ identifier: String) -> String {
        switch identifier {
        case "com.apple.platform.iphonesimulator": "iOS"
        case "com.apple.platform.watchsimulator": "watchOS"
        case "com.apple.platform.appletvsimulator": "tvOS"
        case "com.apple.platform.xrsimulator": "visionOS"
        default: identifier.split(separator: ".").last.map(String.init) ?? "Simulator"
        }
    }

    /// Runs simctl for each runtime item. A booted simulator on that runtime is shut down first,
    /// which simctl does on its own.
    public static func deleteRuntimes(_ items: [LeftoverItem]) -> [RemovalResult] {
        items.compactMap { item in
            guard case .simulatorRuntime(let id) = item.removal else { return nil }
            do {
                _ = try Shell.run("/usr/bin/xcrun", ["simctl", "runtime", "delete", id], timeout: 300)
                return RemovalResult(url: item.url, outcome: .deleted)
            } catch let failure as Shell.Failure {
                return RemovalResult(url: item.url, outcome: .failed(failure.output.trimmingCharacters(in: .whitespacesAndNewlines)))
            } catch {
                return RemovalResult(url: item.url, outcome: .failed(error.localizedDescription))
            }
        }
    }

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
