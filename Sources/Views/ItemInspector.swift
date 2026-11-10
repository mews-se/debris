import AppKit
import DebrisKit
import SwiftUI

/// The panel beside each list: where the selected file is, why it is listed and which installed
/// app it was held against, so a borderline case can be judged without leaving the app.
struct ItemInspector: View {
    @Environment(AppModel.self) private var model
    let item: LeftoverItem?
    let module: Module

    var body: some View {
        Group {
            if let item {
                details(item)
            } else {
                ContentUnavailableView("No Selection", systemImage: "info.circle",
                                       description: Text("Click a row in the list to see why it is there."))
            }
        }
        .inspectorColumnWidth(min: 260, ideal: 320, max: 460)
    }

    private func details(_ item: LeftoverItem) -> some View {
        Form {
            Section {
                HStack(spacing: 10) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                        .resizable()
                        .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.headline).lineLimit(3)
                        Text(item.location.title).foregroundStyle(.secondary)
                    }
                }
                if module == .leftovers {
                    ConfidenceTag(confidence: item.classification.confidence)
                }
            }
            Section(reasonTitle) {
                ForEach(item.classification.evidence, id: \.self) { Text($0) }
            }
            comparison(item)
            Section("Path") {
                Text(item.url.path)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                HStack {
                    Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
                    Button("Copy Path") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(item.url.path, forType: .string)
                    }
                }
            }
            Section {
                LabeledContent("Size", value: item.size.map { Format.size($0) } ?? "Not measured")
                LabeledContent(item.removal == .trash ? "Modified" : "Last used",
                               value: item.modified.map { Format.date($0) } ?? "Unknown")
                LabeledContent("Removal", value: removal(item))
            }
        }
        .formStyle(.grouped)
    }

    private var reasonTitle: String {
        switch module {
        case .leftovers: "Why it is listed"
        case .uninstall: "Why it belongs to the app"
        case .clean: "Why it is safe to remove"
        }
    }

    @ViewBuilder
    private func comparison(_ item: LeftoverItem) -> some View {
        let inventory = model.inventory
        let apps = inventory.apps(matching: item.classification.ownership)
        switch item.classification.ownership {
        case .installed:
            if let app = apps.first {
                Section("Belongs to") { AppLine(app: app) }
            }
        case .vendor(let vendor):
            Section("Same vendor, still installed") {
                if apps.isEmpty { Text(vendor) } else { appList(apps) }
            }
        case .name(let name):
            Section("Similar name, still installed") {
                if apps.isEmpty {
                    Text("\"\(name)\" is the name of an installed Homebrew package, command-line tool or helper.")
                } else {
                    appList(apps)
                }
            }
        case .unknown where module == .leftovers:
            let helpers = inventory.apps.count - inventory.topLevelApps.count
            Section("Compared against") {
                Text("\(inventory.topLevelApps.count) apps, \(helpers) helpers and extensions inside them, \(inventory.homebrewFormulae.count) Homebrew packages and \(inventory.commands.count) command-line tools. None of them matches.")
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func appList(_ apps: [InstalledApp]) -> some View {
        ForEach(apps.prefix(8)) { AppLine(app: $0) }
        if apps.count > 8 {
            Text("and \(apps.count - 8) more").foregroundStyle(.secondary)
        }
    }

    private func removal(_ item: LeftoverItem) -> String {
        if let reason = item.blockedReason { return "Cannot be moved. \(reason)" }
        if item.removal != .trash { return "Deleted right away through simctl" }
        if item.requiresAdmin { return "To the Trash, behind an administrator password" }
        return "To the Trash"
    }
}

private struct AppLine: View {
    let app: InstalledApp

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                .resizable()
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                Text(app.url.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
        }
    }
}

/// Toolbar button every module carries next to Rescan.
struct InspectorButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Toggle(isOn: $model.showInspector) {
            Label("Details", systemImage: "info.circle")
        }
        .keyboardShortcut("i", modifiers: [.command, .option])
        .help("Show why the selected row is listed (⌥⌘I)")
    }
}

extension View {
    /// Puts the inspector for the module's focused row next to the view.
    func itemInspector(_ item: LeftoverItem?, module: Module) -> some View {
        modifier(ItemInspectorPanel(item: item, module: module))
    }
}

private struct ItemInspectorPanel: ViewModifier {
    @Environment(AppModel.self) private var model
    let item: LeftoverItem?
    let module: Module

    func body(content: Content) -> some View {
        @Bindable var model = model
        content.inspector(isPresented: $model.showInspector) {
            ItemInspector(item: item, module: module)
        }
    }
}
