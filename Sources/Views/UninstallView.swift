import DebrisKit
import SwiftUI

struct UninstallView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var confirmRemoval = false

    private var uninstall: UninstallModel { model.uninstall }

    private var apps: [InstalledApp] {
        model.inventory.topLevelApps.filter { app in
            switch app.source {
            case .applications, .userApplications, .homebrewCask: true
            default: false
            }
        }.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.bundleID.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        @Bindable var uninstall = model.uninstall
        HSplitView {
            appList
                .frame(minWidth: 300, idealWidth: 360, maxWidth: 480)
            detail
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Uninstall")
        .searchable(text: $search, placement: .toolbar, prompt: "App name or identifier")
        .confirmationDialog(confirmTitle, isPresented: $confirmRemoval, titleVisibility: .visible) {
            Button(uninstall.runningApplication == nil ? "Move to Trash" : "Quit and Move to Trash", role: .destructive) {
                Task {
                    await uninstall.remove()
                    await model.refreshInventory()
                }
            }
        } message: {
            Text(confirmMessage)
        }
        .sheet(isPresented: $uninstall.showResults) {
            RemovalResultsSheet(results: uninstall.removalResults) { uninstall.showResults = false }
        }
    }

    private var confirmTitle: String {
        guard let report = uninstall.report else { return "" }
        let count = uninstall.removableSelection.count
        let size = Format.size(uninstall.selectedSize)
        if uninstall.bundleSelected {
            return "Move \(report.app.name) and \(max(count - 1, 0)) related items (\(size)) to the Trash?"
        }
        return "Move \(count) items belonging to \(report.app.name) (\(size)) to the Trash?"
    }

    private var confirmMessage: String {
        var text = "Everything stays in the Trash until you empty it."
        if uninstall.selectedAdminCount > 0 {
            text += " \(uninstall.selectedAdminCount) of the items are owned by the system, so macOS will ask for an administrator password."
        }
        return text
    }

    private var appList: some View {
        List(apps, selection: Binding(
            get: { uninstall.selectedAppID },
            set: { id in uninstall.select(apps.first { $0.id == id }, inventory: model.inventory) }
        )) { app in
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                    .resizable()
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name)
                    Text(app.bundleID).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                if case .homebrewCask = app.source {
                    Image(systemName: "mug").foregroundStyle(.secondary).help("Installed by Homebrew")
                }
                if let version = app.version {
                    Text(version).font(.caption).foregroundStyle(.secondary)
                }
            }
            .tag(app.id)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let report = uninstall.report {
            VStack(spacing: 0) {
                header(report)
                Divider()
                itemList(report)
                Divider()
                footer(report)
            }
        } else if uninstall.isLoading {
            VStack(spacing: 12) {
                ProgressView(value: uninstall.progress?.fraction)
                    .frame(maxWidth: 320)
                Text(uninstall.progress?.phase ?? "Looking")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 420)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView("Pick an app", systemImage: "trash",
                                   description: Text("Debris shows the app together with its containers, preferences, caches, helpers and receipts, so all of it goes at once."))
        }
    }

    private func header(_ report: AppOwnedItems) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: report.app.url.path))
                .resizable()
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(report.app.name).font(.title2.weight(.semibold))
                    if let version = report.app.version {
                        Text(version).foregroundStyle(.secondary)
                    }
                    if uninstall.runningApplication != nil {
                        Text("Running")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.green.opacity(0.15), in: Capsule())
                            .foregroundStyle(.green)
                    }
                }
                Text(report.app.bundleID).font(.callout).foregroundStyle(.secondary)
                Text(Format.homeRelative(report.app.url) + "/" + report.app.url.lastPathComponent)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                if let cask = report.cask {
                    Text("Installed by Homebrew as the cask \(cask). Run brew uninstall --cask \(cask) afterwards so Homebrew stops listing it.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text(Format.size(report.totalSize)).font(.title3.weight(.medium)).monospacedDigit()
                Text("\(report.items.count) related items").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }

    private func itemList(_ report: AppOwnedItems) -> some View {
        let grouped = Dictionary(grouping: report.items, by: \.location.kind)
        let kinds = LeftoverLocation.Kind.allCases.filter { grouped[$0] != nil }
        return List {
            Section {
                ItemRow(item: report.bundle, isSelected: uninstall.isSelected(report.bundle), onToggle: { uninstall.setSelected(report.bundle, $0) }, showLocation: false)
            } header: {
                sectionHeader("Application", items: [report.bundle])
            }
            ForEach(kinds, id: \.self) { kind in
                let items = grouped[kind] ?? []
                Section {
                    ForEach(items) { item in
                        ItemRow(item: item, isSelected: uninstall.isSelected(item), onToggle: { uninstall.setSelected(item, $0) }, showLocation: false)
                    }
                } header: {
                    sectionHeader(kind.rawValue, items: items)
                }
            }
            if !report.unreadable.isEmpty {
                Section {
                    ForEach(report.unreadable) { location in
                        Label(location.url.path, systemImage: "eye.slash").foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Not readable without Full Disk Access").textCase(nil)
                }
            }
        }
        .listStyle(.inset)
    }

    private func sectionHeader(_ title: String, items: [LeftoverItem]) -> some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            Text("\(items.count) items").foregroundStyle(.secondary)
            Text(Format.size(items.reduce(0) { $0 + ($1.size ?? 0) })).monospacedDigit().frame(width: 80, alignment: .trailing)
        }
        .textCase(nil)
        .padding(.vertical, 2)
    }

    private func footer(_ report: AppOwnedItems) -> some View {
        HStack(spacing: 16) {
            if !model.fullDiskAccess {
                Button("Grant Full Disk Access") { model.openFullDiskAccessSettings() }
                    .help("Containers and other protected folders stay hidden without it")
            }
            Spacer()
            if uninstall.selectedAdminCount > 0 {
                Label("\(uninstall.selectedAdminCount) need an administrator password", systemImage: "lock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button {
                confirmRemoval = true
            } label: {
                Label(uninstall.bundleSelected
                      ? "Move App and \(max(uninstall.removableSelection.count - 1, 0)) Items to Trash (\(Format.size(uninstall.selectedSize)))"
                      : "Move \(uninstall.removableSelection.count) Items to Trash (\(Format.size(uninstall.selectedSize)))",
                      systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .disabled(uninstall.removableSelection.isEmpty || uninstall.isRemoving)
        }
        .padding(12)
        .background(.bar)
    }
}
