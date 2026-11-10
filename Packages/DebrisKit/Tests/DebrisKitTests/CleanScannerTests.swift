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

    @Test func olderRuntimesLeaveTheNewestOfEachPlatform() throws {
        let json = """
        {
          "A": {"identifier": "A", "deletable": true, "version": "26.5", "build": "23F77", "platformIdentifier": "com.apple.platform.iphonesimulator",
                "path": "/System/Library/AssetsV2/a", "sizeBytes": 8494282293, "lastUsedAt": "2026-11-07T00:49:41Z"},
          "B": {"identifier": "B", "deletable": true, "version": "27.1", "build": "24A94425", "platformIdentifier": "com.apple.platform.iphonesimulator",
                "path": "/System/Library/AssetsV2/b", "sizeBytes": 7874743137},
          "C": {"identifier": "C", "deletable": true, "version": "9.3", "build": "13E233", "platformIdentifier": "com.apple.platform.iphonesimulator",
                "path": "/c", "sizeBytes": 1},
          "D": {"identifier": "D", "deletable": false, "version": "28.0", "build": "25A1", "platformIdentifier": "com.apple.platform.iphonesimulator",
                "path": "/d", "sizeBytes": 1},
          "E": {"identifier": "E", "deletable": true, "version": "12.0", "build": "23R1", "platformIdentifier": "com.apple.platform.watchsimulator",
                "path": "/e", "sizeBytes": 1}
        }
        """
        let older = Simulators.olderRuntimes(in: Data(json.utf8))
        #expect(older.map(\.id) == ["C", "A"], "9.3 sorts before 26.5, 27.1 is the newest one simctl may delete, watchOS has only one")

        let location = LeftoverLocation(kind: .developer, domain: .user, url: URL(fileURLWithPath: "/Library/Developer/CoreSimulator"))
        let item = try #require(older.last).item(location: location)
        #expect(item.title == "iOS 26.5 (23F77)")
        #expect(item.size == 8494282293)
        #expect(item.modified != nil)
        #expect(item.removal == .simulatorRuntime(id: "A"))
        #expect(!item.requiresAdmin)
    }
}
