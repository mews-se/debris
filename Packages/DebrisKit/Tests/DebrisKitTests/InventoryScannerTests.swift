import Foundation
import Testing
@testable import DebrisKit

struct InventoryScannerTests {
    func bundle(_ bundleID: String, at url: URL) throws {
        let contents = url.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": bundleID, "CFBundleName": url.deletingPathExtension().lastPathComponent]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
    }

    @Test func appsShippedInsideAnAppAreFoundUnderNodeModules() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("debris-inventory-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let outer = root.appendingPathComponent("Outer.app")
        try bundle("com.example.outer", at: outer)
        let inner = outer.appendingPathComponent("Contents/Resources/node_modules/pkg/Inner.app")
        try bundle("com.example.inner", at: inner)
        try bundle("com.example.deeper", at: inner.appendingPathComponent("Contents/SharedSupport/Deeper.app"))
        try bundle("com.example.stray", at: root.appendingPathComponent("node_modules/Stray.app"))

        let options = InventoryScanner.Options(roots: [root], useSpotlight: false, readSigning: false, homebrewPrefixes: [])
        let inventory = await InventoryScanner(options: options).scan()
        #expect(inventory.contains(bundleID: "com.example.outer"))
        #expect(inventory.contains(bundleID: "com.example.inner"), "Electron apps ship whole apps under node_modules")
        #expect(inventory.contains(bundleID: "com.example.deeper"))
        #expect(inventory.app(for: "com.example.inner")?.source == .embedded)
        #expect(!inventory.contains(bundleID: "com.example.stray"), "node_modules outside an app is still skipped")
    }
}
