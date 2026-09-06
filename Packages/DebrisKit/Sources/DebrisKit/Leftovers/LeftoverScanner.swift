import Foundation

public actor LeftoverScanner {
    private let classifier: Classifier
    private let locations: [LeftoverLocation]

    public init(inventory: AppInventory, protection: ProtectionRules = .standard,
                locations: [LeftoverLocation]? = nil) {
        self.classifier = Classifier(inventory: inventory, protection: protection)
        self.locations = locations ?? LocationCatalog.standard()
    }

    public struct Result: Sendable {
        public var items: [LeftoverItem]
        public var unreadable: [LeftoverLocation]
    }

    public func scan(measureSizes: Bool = true,
                     progress: (@Sendable (ScanProgress) -> Void)? = nil) async -> Result {
        var items: [LeftoverItem] = []
        var unreadable: [LeftoverLocation] = []
        let fm = FileManager.default
        for (index, location) in locations.enumerated() {
            progress?(ScanProgress(phase: "Looking in \(location.url.path)", completed: index, total: locations.count))
            guard fm.fileExists(atPath: location.url.path) else { continue }
            if location.kind == .systemExtensions {
                items += stagedExtensions(at: location)
                continue
            }
            let entries: [String]
            do {
                entries = try fm.contentsOfDirectory(atPath: location.url.path)
            } catch {
                unreadable.append(location)
                continue
            }
            for entry in entries {
                if location.kind != .dotfiles, entry.hasPrefix(".") { continue }
                if location.kind == .dotfiles, !entry.hasPrefix(".") { continue }
                let url = location.url.appendingPathComponent(entry)
                if location.kind == .binaries, !isDanglingSymlink(url) { continue }
                let identifier = IdentifierParser.identifier(fromName: entry)
                guard let classification = classifier.classify(name: entry, identifier: identifier, location: location)
                else { continue }
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                items.append(LeftoverItem(url: url, location: location, identifier: identifier,
                                          classification: classification, modified: modified))
            }
            await Task.yield()
        }
        if measureSizes {
            let total = items.count
            progress?(ScanProgress(phase: "Measuring sizes", completed: 0, total: total))
            items = await FileSizer.measure(items) { done in
                progress?(ScanProgress(phase: "Measuring sizes", completed: done, total: total))
            }
        }
        return Result(items: items, unreadable: unreadable)
    }

    /// A staged extension whose app is gone. Listed so the user knows it is there, but never
    /// moved: with SIP on only macOS itself can remove it.
    private func stagedExtensions(at location: LeftoverLocation) -> [LeftoverItem] {
        SystemExtensions.staged(in: location.url).compactMap { entry in
            if let app = entry.originApp, FileManager.default.fileExists(atPath: app) { return nil }
            guard var classification = classifier.classify(name: entry.identifier, identifier: entry.identifier, location: location)
            else { return nil }
            if let app = entry.originApp { classification.evidence.append("Installed by \(app), which is gone") }
            let modified = (try? entry.bundleURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            return LeftoverItem(url: entry.bundleURL, location: location, identifier: entry.identifier,
                                classification: classification, modified: modified,
                                blockedReason: SystemExtensions.blockedReason)
        }
    }

    private func isDanglingSymlink(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]), values.isSymbolicLink == true
        else { return false }
        return !FileManager.default.fileExists(atPath: url.resolvingSymlinksInPath().path)
    }
}
