import DebrisKit
import Foundation
import Observation

@MainActor
@Observable
final class LeftoversModel {
    var groups: [GhostApp] = []
    var isScanning = false
    var progress: ScanProgress?
    var unreadable: [LeftoverLocation] = []
    var hasScanned = false
    var selection: Set<String> = []
    var minimumConfidence: Confidence = .high
    var removalResults: [RemovalResult] = []
    var showResults = false
    var isRemoving = false

    var visibleGroups: [GhostApp] {
        groups.compactMap { group in
            let items = group.items.filter { $0.classification.confidence >= minimumConfidence }
            return items.isEmpty ? nil : GhostApp(key: group.key, title: group.title, items: items)
        }
    }

    var visibleItems: [LeftoverItem] { visibleGroups.flatMap(\.items) }
    var selectedItems: [LeftoverItem] { visibleItems.filter { selection.contains($0.id) } }
    var selectedSize: Int64 { selectedItems.reduce(0) { $0 + ($1.size ?? 0) } }
    var removableSelection: [LeftoverItem] { selectedItems.filter(\.isRemovable) }
    var selectedAdminCount: Int { removableSelection.filter(\.requiresAdmin).count }
    var totalVisibleSize: Int64 { visibleItems.reduce(0) { $0 + ($1.size ?? 0) } }

    func scan(inventory: AppInventory) async {
        isScanning = true
        progress = ScanProgress(phase: "Starting")
        selection = []
        let scanner = LeftoverScanner(inventory: inventory)
        let result = await scanner.scan { [weak self] progress in
            Task { @MainActor in self?.progress = progress }
        }
        groups = Grouping.groups(from: result.items)
        unreadable = result.unreadable
        hasScanned = true
        isScanning = false
        progress = nil
        selectLikely()
    }

    func selectLikely() {
        selection = Set(visibleItems.filter { $0.classification.confidence == .high && $0.isRemovable }.map(\.id))
    }

    func clearSelection() {
        selection = []
    }

    func isSelected(_ item: LeftoverItem) -> Bool {
        selection.contains(item.id)
    }

    func setSelected(_ item: LeftoverItem, _ on: Bool) {
        guard item.isRemovable else { return }
        if on { selection.insert(item.id) } else { selection.remove(item.id) }
    }

    /// true when every item is selected, false when none, nil when mixed.
    func selectionState(of group: GhostApp) -> Bool? {
        let removable = group.items.filter(\.isRemovable)
        let count = removable.filter { selection.contains($0.id) }.count
        if count == 0 { return false }
        if count == removable.count { return true }
        return nil
    }

    func setSelected(_ group: GhostApp, _ on: Bool) {
        for item in group.items { setSelected(item, on) }
    }

    /// The user's own files go first; system-owned ones follow in one batch behind the
    /// administrator prompt.
    func trashSelected() async {
        let own = removableSelection.filter { !$0.requiresAdmin }.map(\.url)
        let admin = removableSelection.filter(\.requiresAdmin).map(\.url)
        guard !own.isEmpty || !admin.isEmpty else { return }
        isRemoving = true
        let results = await Task.detached { TrashExecutor.trash(own) + AdminRemover.trash(admin) }.value
        let removed = Set(results.filter(\.succeeded).map(\.url.path))
        groups = groups.compactMap { group in
            let items = group.items.filter { !removed.contains($0.url.path) }
            return items.isEmpty ? nil : GhostApp(key: group.key, title: group.title, items: items)
        }
        selection.subtract(removed)
        removalResults = results
        showResults = true
        isRemoving = false
    }
}
