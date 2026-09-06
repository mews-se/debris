import AppKit
import DebrisKit
import Observation

@MainActor
@Observable
final class CleanModel {
    var groups: [CleanGroup] = []
    var isScanning = false
    var progress: ScanProgress?
    var hasScanned = false
    var selection: Set<String> = []
    var removalResults: [RemovalResult] = []
    var showResults = false
    var isRemoving = false
    private var runningBundleIDs: Set<String> = []

    var allItems: [LeftoverItem] { groups.flatMap(\.items) }
    var selectedItems: [LeftoverItem] { allItems.filter { selection.contains($0.id) } }
    var selectedSize: Int64 { selectedItems.reduce(0) { $0 + ($1.size ?? 0) } }
    var totalSize: Int64 { allItems.reduce(0) { $0 + ($1.size ?? 0) } }

    func scan(inventory: AppInventory) async {
        isScanning = true
        progress = ScanProgress(phase: "Starting")
        selection = []
        runningBundleIDs = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier?.lowercased() })
        let scanner = CleanScanner(inventory: inventory)
        groups = await scanner.scan { [weak self] progress in
            Task { @MainActor in self?.progress = progress }
        }
        hasScanned = true
        isScanning = false
        progress = nil
        selectRecommended()
    }

    /// The app that owns a cache is running, so its cache is best left for later.
    func isRunning(_ item: LeftoverItem) -> Bool {
        guard case .installed(let bundleID) = item.classification.ownership else { return false }
        return runningBundleIDs.contains(bundleID.lowercased())
    }

    func selectRecommended() {
        selection = Set(groups.filter(\.rule.selectedByDefault).flatMap(\.items).filter { !isRunning($0) }.map(\.id))
    }

    func clearSelection() {
        selection = []
    }

    func isSelected(_ item: LeftoverItem) -> Bool {
        selection.contains(item.id)
    }

    func setSelected(_ item: LeftoverItem, _ on: Bool) {
        if on { selection.insert(item.id) } else { selection.remove(item.id) }
    }

    func selectionState(of group: CleanGroup) -> Bool? {
        let count = group.items.filter { selection.contains($0.id) }.count
        if count == 0 { return false }
        if count == group.items.count { return true }
        return nil
    }

    func setSelected(_ group: CleanGroup, _ on: Bool) {
        for item in group.items { setSelected(item, on) }
    }

    func trashSelected() async {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        isRemoving = true
        let results = await Task.detached { TrashExecutor.trash(urls) }.value
        let removed = Set(results.filter(\.succeeded).map(\.url.path))
        groups = groups.compactMap { group in
            let items = group.items.filter { !removed.contains($0.url.path) }
            return items.isEmpty ? nil : CleanGroup(rule: group.rule, items: items)
        }
        selection.subtract(removed)
        removalResults = results
        showResults = true
        isRemoving = false
    }
}
