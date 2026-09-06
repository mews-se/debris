import DebrisKit
import SwiftUI

struct CleanView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmTrash = false

    private var clean: CleanModel { model.clean }

    var body: some View {
        @Bindable var clean = model.clean
        VStack(spacing: 0) {
            if clean.isScanning {
                ScanProgressBar(progress: clean.progress)
            }
            if clean.hasScanned {
                if clean.groups.isEmpty {
                    ContentUnavailableView("Nothing to clean", systemImage: "checkmark.seal",
                                           description: Text("None of the rules found anything on this Mac."))
                } else {
                    resultsList
                }
            } else if !clean.isScanning {
                intro
            }
            Divider()
            footer
        }
        .navigationTitle("Clean")
        .toolbar {
            Button("Scan", systemImage: "magnifyingglass") {
                Task { await clean.scan(inventory: model.inventory) }
            }
            .disabled(clean.isScanning || !model.hasInventory)
        }
        .confirmationDialog("Move \(clean.selectedItems.count) items (\(Format.size(clean.selectedSize))) to the Trash?",
                            isPresented: $confirmTrash, titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive) {
                Task { await clean.trashSelected() }
            }
        } message: {
            Text("They stay in the Trash until you empty it.")
        }
        .sheet(isPresented: $clean.showResults) {
            RemovalResultsSheet(results: clean.removalResults) { clean.showResults = false }
        }
    }

    private var intro: some View {
        ContentUnavailableView {
            Label("Clear caches, logs and developer junk", systemImage: "sparkles")
        } description: {
            Text("Each rule names a place, says what lives there and why it is safe to move. App caches are only listed for apps that are still installed; build folders, device support files, package manager caches and installers in Downloads come with their sizes so you can decide.")
                .frame(maxWidth: 520)
        } actions: {
            Button("Scan Now") { Task { await clean.scan(inventory: model.inventory) } }
                .buttonStyle(.borderedProminent)
                .disabled(!model.hasInventory)
        }
    }

    private var resultsList: some View {
        List {
            ForEach(clean.groups) { group in
                Section {
                    ForEach(group.items) { item in
                        ItemRow(item: item, isSelected: clean.isSelected(item), onToggle: { clean.setSelected(item, $0) },
                                showLocation: false, badge: clean.isRunning(item) ? "Running" : nil)
                    }
                } header: {
                    RuleHeader(group: group)
                }
            }
        }
        .listStyle(.inset)
    }

    private var footer: some View {
        HStack(spacing: 16) {
            if clean.hasScanned {
                Text("\(clean.allItems.count) items, \(Format.size(clean.totalSize))")
                    .foregroundStyle(.secondary)
                Button("Select Recommended") { clean.selectRecommended() }
                Button("Select None") { clean.clearSelection() }
                    .disabled(clean.selection.isEmpty)
            }
            Spacer()
            Button {
                confirmTrash = true
            } label: {
                Label("Move \(clean.selectedItems.count) to Trash (\(Format.size(clean.selectedSize)))", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .disabled(clean.selectedItems.isEmpty || clean.isRemoving)
        }
        .padding(12)
        .background(.bar)
    }
}

private struct RuleHeader: View {
    @Environment(AppModel.self) private var model
    let group: CleanGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                SelectionCheckbox(state: model.clean.selectionState(of: group)) { on in
                    model.clean.setSelected(group, on)
                }
                Text(group.rule.title).font(.headline)
                Text(group.rule.category.rawValue)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(group.items.count) items").foregroundStyle(.secondary)
                Text(Format.size(group.totalSize)).monospacedDigit().frame(width: 80, alignment: .trailing)
            }
            Text(group.rule.what + " " + group.rule.why)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .textCase(nil)
        .padding(.vertical, 4)
    }
}
