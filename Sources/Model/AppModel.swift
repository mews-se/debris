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
    let clean = CleanModel()

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

    /// Reads the installed apps again, then repeats whatever the current module was showing.
    func rescan() async {
        await refreshInventory()
        switch module {
        case .leftovers: await leftovers.scan(inventory: inventory)
        case .clean: await clean.scan(inventory: inventory)
        case .uninstall:
            let app = inventory.apps.first { $0.id == uninstall.selectedAppID }
            uninstall.select(app, inventory: inventory)
        case nil: break
        }
    }

    var isBusy: Bool {
        inventoryProgress != nil || leftovers.isScanning || clean.isScanning || uninstall.isLoading
    }

    func openFullDiskAccessSettings() {
        NSWorkspace.shared.open(FullDiskAccess.settingsURL)
    }
}
