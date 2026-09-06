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
        let rules = CleanCatalog.standard(home: home, environment: [:]).filter { $0.scope != .unavailableSimulators }
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
}
