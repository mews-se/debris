import DebrisKit
import SwiftUI

enum Module: String, CaseIterable, Identifiable {
    case uninstall
    case leftovers
    case clean

    var id: String { rawValue }

    var title: String {
        switch self {
        case .uninstall: "Uninstall"
        case .leftovers: "Leftovers"
        case .clean: "Clean"
        }
    }

    var symbol: String {
        switch self {
        case .uninstall: "trash"
        case .leftovers: "archivebox"
        case .clean: "sparkles"
        }
    }
}

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(Module.allCases, selection: $model.module) { module in
                Label(module.title, systemImage: module.symbol).tag(module)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
            .safeAreaInset(edge: .bottom) { InventoryStatus() }
        } detail: {
            switch model.module {
            case .uninstall: UninstallView()
            case .leftovers: LeftoversView()
            case .clean: CleanView()
            case nil: Text("Choose a module").foregroundStyle(.secondary)
            }
        }
    }
}

private struct InventoryStatus: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let progress = model.inventoryProgress {
                ProgressView(value: progress.fraction)
                Text(progress.phase).lineLimit(1).truncationMode(.middle)
            } else if model.hasInventory {
                Text("\(model.inventory.topLevelApps.count) apps installed")
                Text("\(model.inventory.homebrewFormulae.count) Homebrew packages")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.bar)
    }
}
