import Foundation

/// Staged system extensions under /Library/SystemExtensions. The database names the app each
/// one came from, which beats guessing from the identifier.
enum SystemExtensions {
    struct Entry {
        let bundleURL: URL
        let identifier: String
        let originApp: String?
    }

    static let blockedReason = "System extensions are protected by System Integrity Protection. macOS removes them itself once the app that installed them is gone and the Mac has restarted."

    static func staged(in root: URL) -> [Entry] {
        let database = root.appendingPathComponent("db.plist")
        if let data = try? Data(contentsOf: database),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let extensions = plist["extensions"] as? [[String: Any]] {
            return extensions.compactMap { entry in
                guard let identifier = entry["identifier"] as? String,
                      let staged = entry["stagedBundleURL"] as? [String: Any],
                      let relative = staged["relative"] as? String,
                      let url = URL(string: relative), url.isFileURL
                else { return nil }
                let container = (entry["container"] as? [String: Any])?["bundlePath"] as? String
                return Entry(bundleURL: url.standardizedFileURL, identifier: identifier, originApp: container)
            }
        }
        return walk(root)
    }

    private static func walk(_ root: URL) -> [Entry] {
        let fm = FileManager.default
        guard let folders = try? fm.contentsOfDirectory(atPath: root.path) else { return [] }
        var entries: [Entry] = []
        for folder in folders where IdentifierParser.isUUIDName(folder) {
            let url = root.appendingPathComponent(folder)
            for name in (try? fm.contentsOfDirectory(atPath: url.path)) ?? [] {
                let bundle = url.appendingPathComponent(name)
                guard ["dext", "systemextension"].contains(bundle.pathExtension),
                      let info = BundleReader.info(at: bundle) else { continue }
                entries.append(Entry(bundleURL: bundle, identifier: info.bundleID, originApp: nil))
            }
        }
        return entries
    }
}
