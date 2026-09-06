import DebrisKit
import Foundation

@main
struct DebrisCLI {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let measureSizes = !arguments.contains("--no-sizes")
        let minimum: Confidence = arguments.contains("--all") ? .low : .medium

        let started = Date()
        let inventory = await InventoryScanner().scan()
        let elapsed = Int(Date().timeIntervalSince(started))
        print("Installed: \(inventory.topLevelApps.count) apps, \(inventory.apps.count) bundles, \(inventory.homebrewFormulae.count) Homebrew packages (\(elapsed)s)")

        if arguments.contains("--missing") {
            let known = Set(inventory.apps.map(\.url.path))
            let entries = (try? FileManager.default.contentsOfDirectory(atPath: "/Applications")) ?? []
            for entry in entries where entry.hasSuffix(".app") && !known.contains("/Applications/" + entry) {
                print("missing from inventory: /Applications/\(entry)")
            }
            return
        }
        if let index = arguments.firstIndex(of: "--uninstall"), index + 1 < arguments.count {
            let needle = arguments[index + 1].lowercased()
            guard let app = inventory.topLevelApps.first(where: { $0.name.lowercased() == needle })
                ?? inventory.topLevelApps.first(where: { $0.name.lowercased().contains(needle) }) else {
                print("no installed app matches \(needle)"); return
            }
            let report = await OwnedItemsFinder(inventory: inventory).find(for: app, measureSizes: measureSizes)
            let formatter = ByteCountFormatter(); formatter.countStyle = .file
            print("\(app.name) (\(app.bundleID)) at \(app.url.path)")
            for item in report.everything {
                let size = item.size.map { formatter.string(fromByteCount: $0) } ?? "?"
                print("  \(size.padding(toLength: 10, withPad: " ", startingAt: 0)) \(item.location.title.padding(toLength: 24, withPad: " ", startingAt: 0)) \(item.url.path)   [\(item.classification.evidence.first ?? "")]")
            }
            print("  cask: \(report.cask ?? "-")  total: \(formatter.string(fromByteCount: report.totalSize))")
            return
        }
        if arguments.contains("--clean") {
            let groups = await CleanScanner(inventory: inventory).scan(measureSizes: measureSizes)
            let formatter = ByteCountFormatter(); formatter.countStyle = .file
            for group in groups {
                print("\n\(group.rule.title) [\(group.rule.category.rawValue)]  \(formatter.string(fromByteCount: group.totalSize))\(group.rule.selectedByDefault ? "" : "  (not selected by default)")")
                for item in group.items {
                    let size = item.size.map { formatter.string(fromByteCount: $0) } ?? "?"
                    print("  \(size.padding(toLength: 10, withPad: " ", startingAt: 0)) \(item.url.path)")
                }
            }
            let total = groups.reduce(Int64(0)) { $0 + $1.totalSize }
            print("\n\(groups.reduce(0) { $0 + $1.items.count }) items in \(groups.count) rules, \(formatter.string(fromByteCount: total)) in total")
            return
        }
        if let index = arguments.firstIndex(of: "--app"), index + 1 < arguments.count {
            let needle = arguments[index + 1].lowercased()
            for app in inventory.apps where app.name.lowercased().contains(needle) || app.bundleID.lowercased().contains(needle) {
                print("\(app.bundleID)  team=\(app.teamID ?? "-")  groups=\(app.appGroups)  \(app.url.path)")
            }
            let signed = inventory.topLevelApps.filter { $0.teamID != nil }.count
            print("apps with a team id: \(signed) of \(inventory.topLevelApps.count)")
            return
        }

        let scanner = LeftoverScanner(inventory: inventory)
        let result = await scanner.scan(measureSizes: measureSizes)
        let items = result.items.filter { $0.classification.confidence >= minimum }
        let groups = Grouping.groups(from: items)
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file

        for group in groups {
            let size = formatter.string(fromByteCount: group.totalSize)
            let admin = group.needsAdmin ? " [admin]" : ""
            print("\n\(group.title)  \(size)  \(group.confidence.title)\(admin)")
            for item in group.items {
                let itemSize = item.size.map { formatter.string(fromByteCount: $0) } ?? "?"
                print("  \(itemSize.padding(toLength: 10, withPad: " ", startingAt: 0)) \(item.url.path)")
            }
        }
        let total = formatter.string(fromByteCount: items.reduce(0) { $0 + ($1.size ?? 0) })
        print("\n\(items.count) items in \(groups.count) groups, \(total) in total, \(Int(Date().timeIntervalSince(started)))s")
        if !result.unreadable.isEmpty {
            print("Unreadable without Full Disk Access: \(result.unreadable.map(\.url.path).joined(separator: ", "))")
        }
        print("Full Disk Access: \(FullDiskAccess.isGranted() ? "granted" : "not granted")")
    }
}
