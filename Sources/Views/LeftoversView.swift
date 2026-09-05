import DebrisKit
import SwiftUI

struct LeftoversView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmTrash = false

    private var leftovers: LeftoversModel { model.leftovers }

    var body: some View {
        @Bindable var leftovers = model.leftovers
        VStack(spacing: 0) {
            if !model.fullDiskAccess { PermissionBanner() }
            if leftovers.isScanning {
                ScanProgressBar(progress: leftovers.progress)
            }
            if leftovers.hasScanned {
                if leftovers.visibleGroups.isEmpty {
                    ContentUnavailableView("Nothing left behind", systemImage: "checkmark.seal",
                                           description: Text(emptyDescription))
                } else {
                    resultsList
                }
            } else if !leftovers.isScanning {
                intro
            }
            Divider()
            footer
        }
        .navigationTitle("Leftovers")
        .toolbar {
            ToolbarItemGroup {
                Picker("Show", selection: $leftovers.minimumConfidence) {
                    Text("Likely").tag(Confidence.high)
                    Text("Possible").tag(Confidence.medium)
                    Text("Everything").tag(Confidence.low)
                }
                .pickerStyle(.segmented)
                .help("How sure Debris has to be before a file is listed")
                Button("Scan", systemImage: "magnifyingglass") {
                    Task { await leftovers.scan(inventory: model.inventory) }
                }
                .disabled(leftovers.isScanning || !model.hasInventory)
            }
        }
        .confirmationDialog(confirmTitle, isPresented: $confirmTrash, titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive) {
                Task { await leftovers.trashSelected() }
            }
        } message: {
            Text("They stay in the Trash until you empty it.")
        }
        .sheet(isPresented: $leftovers.showResults) {
            RemovalResultsSheet(results: leftovers.removalResults) { leftovers.showResults = false }
        }
    }

    private var emptyDescription: String {
        switch leftovers.minimumConfidence {
        case .high: "No files that clearly belong to an app you no longer have. Switch to Possible to see files whose vendor still has other apps installed."
        case .medium: "Nothing possible either. Everything shows the unclear cases too."
        case .low: "Not a single unexplained file. That is rare."
        }
    }

    private var confirmTitle: String {
        "Move \(leftovers.removableSelection.count) items (\(Format.size(leftovers.selectedSize))) to the Trash?"
    }

    private var intro: some View {
        ContentUnavailableView {
            Label("Find what deleted apps left behind", systemImage: "archivebox")
        } description: {
            Text("Debris compares every file in the usual Library folders against the apps, helpers and Homebrew packages that are actually installed. Whatever has no owner left is listed here, grouped by the app it came from.")
                .frame(maxWidth: 520)
        } actions: {
            Button("Scan Now") { Task { await leftovers.scan(inventory: model.inventory) } }
                .buttonStyle(.borderedProminent)
                .disabled(!model.hasInventory)
        }
    }

    private var resultsList: some View {
        List {
            ForEach(leftovers.visibleGroups) { group in
                Section {
                    ForEach(group.items) { item in
                        LeftoverRow(item: item)
                    }
                } header: {
                    GroupHeader(group: group)
                }
            }
            if !leftovers.unreadable.isEmpty {
                Section {
                    ForEach(leftovers.unreadable) { location in
                        Label(location.url.path, systemImage: "eye.slash").foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Not readable without Full Disk Access")
                }
            }
        }
        .listStyle(.inset)
    }

    private var footer: some View {
        HStack(spacing: 16) {
            if leftovers.hasScanned {
                Text("\(leftovers.visibleItems.count) items, \(Format.size(leftovers.totalVisibleSize))")
                    .foregroundStyle(.secondary)
                Button("Select Likely") { leftovers.selectLikely() }
                Button("Select None") { leftovers.clearSelection() }
                    .disabled(leftovers.selection.isEmpty)
            }
            Spacer()
            if leftovers.selectedAdminCount > 0 {
                Label("\(leftovers.selectedAdminCount) selected items need an administrator and are skipped for now", systemImage: "lock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button {
                confirmTrash = true
            } label: {
                Label("Move \(leftovers.removableSelection.count) to Trash (\(Format.size(leftovers.selectedSize)))", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .disabled(leftovers.removableSelection.isEmpty || leftovers.isRemoving)
        }
        .padding(12)
        .background(.bar)
    }
}

private struct ScanProgressBar: View {
    let progress: ScanProgress?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: progress?.fraction)
            Text(progress?.phase ?? "Scanning")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

private struct GroupHeader: View {
    @Environment(AppModel.self) private var model
    let group: GhostApp

    var body: some View {
        HStack(spacing: 10) {
            let state = model.leftovers.selectionState(of: group)
            Button {
                model.leftovers.setSelected(group, state != true)
            } label: {
                Image(systemName: state == true ? "checkmark.square.fill" : state == nil ? "minus.square.fill" : "square")
                    .foregroundStyle(state == false ? .secondary : Color.accentColor)
            }
            .buttonStyle(.plain)
            Text(group.title).font(.headline)
            ConfidenceTag(confidence: group.confidence)
            if group.needsAdmin {
                Image(systemName: "lock").foregroundStyle(.secondary).help("Some of these files are owned by the system")
            }
            Spacer()
            Text("\(group.items.count) items").foregroundStyle(.secondary)
            Text(Format.size(group.totalSize)).monospacedDigit().frame(width: 80, alignment: .trailing)
        }
        .textCase(nil)
        .padding(.vertical, 4)
    }
}

private struct LeftoverRow: View {
    @Environment(AppModel.self) private var model
    let item: LeftoverItem

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { model.leftovers.isSelected(item) },
                set: { model.leftovers.setSelected(item, $0) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .disabled(item.requiresAdmin)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).lineLimit(1).truncationMode(.middle)
                Text(Format.homeRelative(item.url))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if item.requiresAdmin {
                Image(systemName: "lock").foregroundStyle(.secondary)
                    .help("Owned by the system; removing it needs an administrator")
            }
            Text(item.location.title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .leading)
            Text(Format.date(item.modified))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .trailing)
            Text(Format.size(item.size)).monospacedDigit().frame(width: 80, alignment: .trailing)
        }
        .help(item.classification.evidence.joined(separator: "\n"))
        .contextMenu {
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.url.path, forType: .string)
            }
        }
    }
}

struct ConfidenceTag: View {
    let confidence: Confidence

    var body: some View {
        Text(confidence.title)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch confidence {
        case .high: .green
        case .medium: .orange
        case .low: .secondary
        }
    }
}
