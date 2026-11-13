import Foundation
import Testing
@testable import DebrisKit

struct CleanScannerTests {
    let inventory = AppInventory(apps: [
        InstalledApp(bundleID: "com.microsoft.Outlook", name: "Microsoft Outlook", url: URL(fileURLWithPath: "/Applications/Microsoft Outlook.app"), source: .applications),
    ])

    func home() throws -> URL {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("debris-clean-\(UUID().uuidString)")
        let fm = FileManager.default
        for folder in ["Library/Caches/com.microsoft.Outlook", "Library/Caches/com.vivaldi.Vivaldi", "Library/Caches/com.apple.Safari",
                       "Library/Caches/Homebrew/downloads", "Library/Developer/Xcode/DerivedData/App-abc", "Library/Developer/Xcode/DerivedData/ModuleCache.noindex",
                       "Downloads/folder.dmg", ".npm/_cacache/index", "Library/Caches/pip"] {
            try fm.createDirectory(at: home.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        for file in ["Library/Caches/com.microsoft.Outlook/x", "Library/Caches/com.vivaldi.Vivaldi/x", "Library/Caches/Homebrew/downloads/x",
                     "Downloads/Installer.dmg", "Downloads/Tool.PKG", "Downloads/notes.txt", ".npm/_cacache/index/x"] {
            try Data("x".utf8).write(to: home.appendingPathComponent(file))
        }
        return home
    }

    func groups(home: URL) async -> [String: [String]] {
        let rules = CleanCatalog.standard(home: home, environment: [:]).filter { ![.unavailableSimulators, .simulatorRuntimes].contains($0.scope) }
        let scanner = CleanScanner(inventory: inventory, rules: rules)
        let result = await scanner.scan(measureSizes: false)
        return Dictionary(uniqueKeysWithValues: result.map { ($0.rule.id, $0.items.map(\.name)) })
    }

    @Test func appCachesOnlyForInstalledApps() async throws {
        let home = try home()
        defer { try? FileManager.default.removeItem(at: home) }
        let result = await groups(home: home)
        #expect(result["app-caches"] == ["com.microsoft.Outlook"], "Vivaldi is a leftover, Safari is Apple's, Homebrew and pip have rules of their own")
    }

    @Test func rulesResolveChildrenFoldersAndInstallers() async throws {
        let home = try home()
        defer { try? FileManager.default.removeItem(at: home) }
        let result = await groups(home: home)
        #expect(result["derived-data"] == ["App-abc", "ModuleCache.noindex"])
        #expect(result["homebrew"] == ["downloads"])
        #expect(result["npm"] == ["_cacache"])
        #expect(result["installers"] == ["Installer.dmg", "Tool.PKG", "folder.dmg"])
        #expect(result["pip"] == nil, "an empty cache folder is not listed")
        #expect(result["cargo"] == nil)
    }

    let general = ["iPhone-17", "iPhone-17-Pro", "iPhone-Air", "iPad-Pro-13-inch-M5"]

    @Test func generalRuntimeStaysBesideADeviceSpecificBuild() throws {
        var simctl = Simctl()
        simctl.add("A", "27.0", "24A5355", devices: general)
        simctl.add("B", "27.1", "24A94425", devices: ["iPhone-Duo"])
        #expect(try simctl.older() == [], "27.1 only runs the iPhone Duo, so 27.0 is the last runtime for every other device")

        simctl.add("C", "26.5", "23F77", devices: general)
        #expect(try simctl.older() == ["C"])
    }

    @Test func olderRuntimeIsListedWhenANewerOneRunsAllItsDevices() throws {
        var simctl = Simctl()
        simctl.add("A", "26.5", "23F77", devices: general, size: 8494282293, lastUsed: "2026-11-07T00:49:41Z")
        simctl.add("B", "27.0", "24A5355", devices: general + ["iPhone-18"])
        let older = try simctl.olderRuntimes()
        #expect(older.map(\.id) == ["A"])

        let location = LeftoverLocation(kind: .developer, domain: .user, url: URL(fileURLWithPath: "/Library/Developer/CoreSimulator"))
        let item = try #require(older.first).item(location: location)
        #expect(item.title == "iOS 26.5 (23F77)")
        #expect(item.classification.evidence.first == "Every device it simulates also runs on iOS 27.0 (24A5355)")
        #expect(item.size == 8494282293)
        #expect(item.modified != nil)
        #expect(item.removal == .simulatorRuntime(id: "A"))
        #expect(!item.requiresAdmin)
    }

    @Test func newerBuildsCoverOlderGeneralAndDeviceSpecificOnes() throws {
        var simctl = Simctl()
        simctl.add("A", "27.0", "24A5355", devices: general)
        simctl.add("B", "27.1", "24A94425", devices: ["iPhone-Duo"])
        simctl.add("C", "27.2", "24B8117", devices: general)
        simctl.add("D", "27.2", "24B91016s", devices: ["iPhone-Duo"])
        let older = try simctl.olderRuntimes()
        #expect(older.map(\.id) == ["A", "B"])
        #expect(older.map(\.coveredBy) == [["iOS 27.2 (24B8117)"], ["iOS 27.2 (24B91016s)"]])
    }

    @Test func runtimeStaysWhileItIsTheLastForADevice() throws {
        var simctl = Simctl()
        simctl.add("A", "26.5", "23F77", devices: ["iPhone-11"] + general)
        simctl.add("B", "27.0", "24A5355", devices: general)
        #expect(try simctl.older() == [], "27.0 no longer runs the iPhone 11")
    }

    @Test func onlyRuntimesThatStayCoverOlderOnes() throws {
        var kept = Simctl()
        kept.add("A", "27.0", "24A5355", devices: general)
        kept.add("B", "27.2", "24C5089", devices: general, deletable: false)
        #expect(try kept.older() == ["A"], "a runtime simctl cannot delete stays")

        var unavailable = Simctl()
        unavailable.add("A", "27.0", "24A5355", devices: general)
        unavailable.add("B", "27.2", "24C5089", devices: general, available: false)
        #expect(try unavailable.older() == [], "a runtime that cannot run covers nothing")

        var platforms = Simctl()
        platforms.add("A", "27.0", "24A5355", devices: general)
        platforms.add("B", "26.0", "23R354", devices: ["Apple-Watch-Series-11-46mm"], platform: "watchOS")
        #expect(try platforms.older() == [])
    }

    @Test func runtimesWithUnknownDevicesAreNeverListed() throws {
        var unlisted = Simctl()
        unlisted.add("A", "26.5", "23F77", devices: general, listed: false)
        unlisted.add("B", "27.0", "24A5355", devices: general)
        #expect(try unlisted.older() == [], "simctl list runtimes does not report it")

        var empty = Simctl()
        empty.add("A", "26.5", "23F77", devices: [])
        empty.add("B", "27.0", "24A5355", devices: general)
        #expect(try empty.older() == [])

        var unmounted = Simctl()
        unmounted.add("A", "26.5", "23F77", devices: general, mounted: false)
        unmounted.add("B", "27.0", "24A5355", devices: general)
        #expect(try unmounted.older() == ["A"], "matched by runtime identifier and build")
    }
}

/// What simctl runtime list -j and simctl list -j runtimes print for a set of runtimes.
private struct Simctl {
    var images: [String: Any] = [:]
    var runtimes: [[String: Any]] = []

    mutating func add(_ id: String, _ version: String, _ build: String, devices: [String], platform: String = "iOS",
                      size: Int64 = 8_000_000_000, lastUsed: String? = nil, deletable: Bool = true, available: Bool = true,
                      listed: Bool = true, mounted: Bool = true) {
        let runtimeID = "com.apple.CoreSimulator.SimRuntime.\(platform)-\(version.replacingOccurrences(of: ".", with: "-"))"
        let bundlePath = "/private/var/run/com.apple.security.cryptexd/mnt/\(id)/Library/Developer/CoreSimulator/Profiles/Runtimes/\(platform) \(version).simruntime"
        var image: [String: Any] = [
            "identifier": id, "deletable": deletable, "version": version, "build": build, "sizeBytes": size,
            "platformIdentifier": platform == "watchOS" ? "com.apple.platform.watchsimulator" : "com.apple.platform.iphonesimulator",
            "path": "/System/Library/AssetsV2/com_apple_MobileAsset_\(platform)SimulatorRuntime/\(id).asset/AssetData",
            "runtimeIdentifier": runtimeID, "state": "Ready",
        ]
        if mounted { image["runtimeBundlePath"] = bundlePath }
        if let lastUsed { image["lastUsedAt"] = lastUsed }
        images[id] = image
        guard listed else { return }
        runtimes.append([
            "identifier": runtimeID, "name": "\(platform) \(version)", "platform": platform, "version": version,
            "buildversion": build, "bundlePath": bundlePath, "isAvailable": available,
            "supportedDeviceTypes": devices.map { ["identifier": "com.apple.CoreSimulator.SimDeviceType.\($0)", "name": $0] },
        ])
    }

    func olderRuntimes() throws -> [Simulators.Runtime] {
        Simulators.olderRuntimes(images: try JSONSerialization.data(withJSONObject: images),
                                 runtimes: try JSONSerialization.data(withJSONObject: ["runtimes": runtimes]))
    }

    func older() throws -> [String] { try olderRuntimes().map(\.id) }
}
