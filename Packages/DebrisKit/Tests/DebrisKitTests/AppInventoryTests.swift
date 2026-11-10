import Foundation
import Testing
@testable import DebrisKit

struct AppInventoryTests {
    let inventory = AppInventory(apps: [
        InstalledApp(bundleID: "com.microsoft.Word", name: "Microsoft Word", url: URL(fileURLWithPath: "/Applications/Microsoft Word.app"), source: .applications),
        InstalledApp(bundleID: "com.microsoft.Excel", name: "Microsoft Excel", url: URL(fileURLWithPath: "/Applications/Microsoft Excel.app"), source: .applications),
        InstalledApp(bundleID: "com.microsoft.Word.Helper", name: "Helper",
                     url: URL(fileURLWithPath: "/Applications/Microsoft Word.app/Contents/Helpers/Helper.app"), source: .embedded),
        InstalledApp(bundleID: "com.coconut-flavour.coconutBattery", name: "coconutBattery", url: URL(fileURLWithPath: "/Applications/coconutBattery.app"), source: .applications),
    ])

    @Test func ownershipPointsAtTheAppsBehindIt() {
        #expect(inventory.apps(matching: .vendor("com.microsoft")).map(\.name) == ["Microsoft Excel", "Microsoft Word"])
        #expect(inventory.apps(matching: .vendor("coconut-flavour")).map(\.name) == ["coconutBattery"])
        #expect(inventory.apps(matching: .installed(bundleID: "com.microsoft.word.helper")).map(\.name) == ["Microsoft Word"],
                "a helper is shown as the app it ships inside")
        #expect(inventory.apps(matching: .name("coconutbattery")).map(\.name) == ["coconutBattery"])
        #expect(inventory.apps(matching: .unknown).isEmpty)
    }
}
