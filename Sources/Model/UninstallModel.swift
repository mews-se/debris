import AppKit
import DebrisKit
import Observation

@MainActor
@Observable
final class UninstallModel {
    var selectedAppID: InstalledApp.ID?
    var report: AppOwnedItems?
    var isLoading = false
    var progress: ScanProgress?
    var selection: Set<String> = []
    var isRemoving = false
    var removalResults: [RemovalResult] = []
    var showResults = false
    var removalNote: String?

    private var loadTask: Task<Void, Never>?

    var runningApplication: NSRunningApplication? {
        guard let report else { return nil }
        return NSRunningApplication.runningApplications(withBundleIdentifier: report.app.bundleID)
            .first { $0.bundleURL == report.app.url }
    }

    var selectedItems: [LeftoverItem] {
        report?.everything.filter { selection.contains($0.id) } ?? []
    }

    var removableSelection: [LeftoverItem] { selectedItems.filter(\.isRemovable) }
    var selectedSize: Int64 { selectedItems.reduce(0) { $0 + ($1.size ?? 0) } }
    var selectedAdminCount: Int { removableSelection.filter(\.requiresAdmin).count }
    var bundleSelected: Bool { report.map { selection.contains($0.bundle.id) } ?? false }

    func select(_ app: InstalledApp?, inventory: AppInventory) {
        loadTask?.cancel()
        selection = []
        report = nil
        guard let app else {
            selectedAppID = nil
            return
        }
        selectedAppID = app.id
        isLoading = true
        progress = ScanProgress(phase: "Looking for everything \(app.name) owns")
        loadTask = Task { [weak self] in
            let finder = OwnedItemsFinder(inventory: inventory)
            let result = await finder.find(for: app) { progress in
                Task { @MainActor in self?.progress = progress }
            }
            guard !Task.isCancelled, let self, self.selectedAppID == app.id else { return }
            self.report = result
            self.selection = Set(result.everything.filter(\.isRemovable).map(\.id))
            self.isLoading = false
            self.progress = nil
        }
    }

    func isSelected(_ item: LeftoverItem) -> Bool { selection.contains(item.id) }

    func setSelected(_ item: LeftoverItem, _ on: Bool) {
        guard item.isRemovable else { return }
        if on { selection.insert(item.id) } else { selection.remove(item.id) }
    }

    /// Quits the app if it is running, then moves the selection to the Trash: the user's own
    /// files first, the bundle last, and system-owned files behind one administrator prompt.
    func remove() async {
        guard let report else { return }
        isRemoving = true
        removalNote = nil
        if let running = runningApplication {
            running.terminate()
            for _ in 0..<25 where !running.isTerminated {
                try? await Task.sleep(for: .milliseconds(200))
            }
            if !running.isTerminated {
                running.forceTerminate()
                try? await Task.sleep(for: .milliseconds(500))
            }
            if !running.isTerminated {
                removalNote = "\(report.app.name) did not quit, so the app bundle was left in place."
            }
        }
        let related = removableSelection.filter { $0.id != report.bundle.id }
        var own = related.filter { !$0.requiresAdmin }.map(\.url)
        var admin = related.filter(\.requiresAdmin).map(\.url)
        if bundleSelected, runningApplication == nil {
            if report.bundle.requiresAdmin { admin.append(report.bundle.url) } else { own.append(report.bundle.url) }
        }
        let results = await Task.detached { TrashExecutor.trash(own) + AdminRemover.trash(admin) }.value
        removalResults = results
        showResults = true
        isRemoving = false
        let removed = Set(results.filter(\.succeeded).map(\.url.path))
        if removed.contains(report.bundle.url.path) {
            self.report = nil
            selectedAppID = nil
            selection = []
        } else {
            self.report?.items.removeAll { removed.contains($0.url.path) }
            selection.subtract(removed)
        }
    }
}
