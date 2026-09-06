import AppKit
import DebrisKit
import Observation

@MainActor
@Observable
final class AppModel {
    var inventory: AppInventory = .empty
    var inventoryProgress: ScanProgress?
    var hasInventory = false
    var fullDiskAccess = false
    var module: Module? = .leftovers

    let leftovers = LeftoversModel()
    let uninstall = UninstallModel()

    func start() async {
        Snapshotter.log("start()")
        refreshPermissions()
        Snapshotter.runIfRequested(model: self)
        await refreshInventory()
        Snapshotter.log("inventory: \(inventory.topLevelApps.count) apps")
    }

    func refreshPermissions() {
        fullDiskAccess = FullDiskAccess.isGranted()
    }

    func refreshInventory() async {
        inventoryProgress = ScanProgress(phase: "Finding installed apps")
        let scanner = InventoryScanner()
        inventory = await scanner.scan { [weak self] progress in
            Task { @MainActor in self?.inventoryProgress = progress }
        }
        hasInventory = true
        inventoryProgress = nil
    }

    func openFullDiskAccessSettings() {
        NSWorkspace.shared.open(FullDiskAccess.settingsURL)
    }
}
