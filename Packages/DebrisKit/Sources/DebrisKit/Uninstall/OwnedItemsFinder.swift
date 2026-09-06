import Foundation

public struct AppOwnedItems: Sendable {
    public let app: InstalledApp
    public var bundle: LeftoverItem
    public var items: [LeftoverItem]
    public var cask: String?
    public var unreadable: [LeftoverLocation]

    public var everything: [LeftoverItem] { [bundle] + items }
    public var totalSize: Int64 { everything.reduce(0) { $0 + ($1.size ?? 0) } }
}

public actor OwnedItemsFinder {
    private let inventory: AppInventory
    private let locations: [LeftoverLocation]

    public init(inventory: AppInventory, locations: [LeftoverLocation]? = nil) {
        self.inventory = inventory
        self.locations = locations ?? LocationCatalog.standard()
    }

    public func find(for app: InstalledApp, measureSizes: Bool = true,
                     progress: (@Sendable (ScanProgress) -> Void)? = nil) async -> AppOwnedItems {
        let matcher = AppMatcher(app: app, inventory: inventory)
        let fm = FileManager.default
        var items: [LeftoverItem] = []
        var unreadable: [LeftoverLocation] = []

        for (index, location) in locations.enumerated() {
            progress?(ScanProgress(phase: "Looking in \(location.url.path)", completed: index, total: locations.count))
            guard fm.fileExists(atPath: location.url.path) else { continue }
            let entries: [String]
            do { entries = try fm.contentsOfDirectory(atPath: location.url.path) } catch {
                unreadable.append(location)
                continue
            }
            for entry in entries {
                if location.kind != .dotfiles, entry.hasPrefix(".") { continue }
                if location.kind == .dotfiles, !entry.hasPrefix(".") { continue }
                let url = location.url.appendingPathComponent(entry)
                if url == app.url { continue }
                let identifier = IdentifierParser.identifier(fromName: entry)
                guard let reason = matcher.reason(forName: entry, identifier: identifier, location: location) else { continue }
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                let classification = Classification(ownership: .installed(bundleID: app.bundleID), confidence: .high, evidence: [reason])
                items.append(LeftoverItem(url: url, location: location, identifier: identifier,
                                          classification: classification, modified: modified))
            }
            await Task.yield()
        }

        let bundleLocation = LeftoverLocation(kind: .application, domain: app.url.path.hasPrefix("/System") ? .system : .user,
                                              url: app.url.deletingLastPathComponent())
        let bundleModified = (try? app.url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        var bundle = LeftoverItem(url: app.url, location: bundleLocation, identifier: app.bundleID,
                                  classification: Classification(ownership: .installed(bundleID: app.bundleID), confidence: .high,
                                                                 evidence: ["The app itself"]),
                                  modified: bundleModified)

        items += Receipts.items(for: app)

        if measureSizes {
            let total = items.count + 1
            progress?(ScanProgress(phase: "Measuring sizes", completed: 0, total: total))
            let measured = await FileSizer.measure([bundle] + items) { done in
                progress?(ScanProgress(phase: "Measuring sizes", completed: done, total: total))
            }
            bundle = measured[0]
            items = Array(measured.dropFirst())
        }

        var cask: String?
        if case .homebrewCask(let name) = app.source { cask = name }
        return AppOwnedItems(app: app, bundle: bundle, items: items.sorted { ($0.size ?? 0) > ($1.size ?? 0) },
                             cask: cask, unreadable: unreadable)
    }
}

enum Receipts {
    static let directory = URL(fileURLWithPath: "/var/db/receipts")

    /// The receipt files of every package that installed the app: the same two files
    /// `pkgutil --forget` deletes, listed so they can go to the Trash with the rest.
    static func items(for app: InstalledApp) -> [LeftoverItem] {
        let location = LeftoverLocation(kind: .receipts, domain: .system, url: directory)
        return packages(installing: app).flatMap { id -> [LeftoverItem] in
            ["plist", "bom"].compactMap { ext in
                let url = directory.appendingPathComponent(id).appendingPathExtension(ext)
                guard FileManager.default.fileExists(atPath: url.path) else { return nil }
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                return LeftoverItem(url: url, location: location, identifier: id,
                                    classification: Classification(ownership: .installed(bundleID: app.bundleID), confidence: .high,
                                                                   evidence: ["Receipt of the package that installed \(app.url.lastPathComponent)"]),
                                    modified: modified)
            }
        }
    }

    /// Package identifiers whose receipt installed the app bundle. `pkgutil --file-info` does
    /// not resolve paths for every receipt, so the candidates are found by name and confirmed
    /// against the receipt's install location and first entry.
    static func packages(installing app: InstalledApp) -> [String] {
        guard let list = try? Shell.run("/usr/sbin/pkgutil", ["--pkgs"], timeout: 15) else { return [] }
        let appName = Identifier.normalized(app.name)
        let words = AppMatcher.productWords(of: app.bundleID).union([appName]).filter { $0.count >= 4 }
        let vendor = Identifier.vendor(of: app.bundleID)
        let all = list.split(separator: "\n").map(String.init)
        let byName = all.filter { id in words.contains { Identifier.normalized(id).contains($0) } }
        let byVendor = all.filter { $0.lowercased().hasPrefix(vendor + ".") && !byName.contains($0) }
        var matches: [String] = []
        for id in (byName + byVendor).prefix(60) {
            guard let info = try? Shell.run("/usr/sbin/pkgutil", ["--pkg-info", id], timeout: 10),
                  let files = try? Shell.run("/usr/sbin/pkgutil", ["--files", id], timeout: 10)
            else { continue }
            var location = "/"
            var volume = "/"
            for line in info.split(separator: "\n") {
                if line.hasPrefix("location:") { location = line.dropFirst("location:".count).trimmingCharacters(in: .whitespaces) }
                if line.hasPrefix("volume:") { volume = line.dropFirst("volume:".count).trimmingCharacters(in: .whitespaces) }
            }
            let root = (volume as NSString).appendingPathComponent(location)
            let bundleName = app.url.lastPathComponent
            // Microsoft AutoUpdate records its receipts against a staging clone folder, so a
            // top-level entry with the bundle's name counts even when the location does not.
            let installsBundle = files.split(separator: "\n").contains { entry in
                let path = (root as NSString).appendingPathComponent(String(entry))
                return path == app.url.path || String(entry) == bundleName
            }
            if installsBundle { matches.append(id) }
        }
        return matches
    }
}
