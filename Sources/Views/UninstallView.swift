import DebrisKit
import SwiftUI

struct UninstallView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var selected: InstalledApp.ID?

    private var apps: [InstalledApp] {
        model.inventory.topLevelApps.filter { app in
            switch app.source {
            case .applications, .userApplications, .homebrewCask: true
            default: false
            }
        }.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.bundleID.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        HSplitView {
            List(apps, selection: $selected) { app in
                HStack(spacing: 10) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                        .resizable()
                        .frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(app.name)
                        Text(app.bundleID).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let version = app.version {
                        Text(version).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .tag(app.id)
            }
            .frame(minWidth: 320, idealWidth: 380)
            .searchable(text: $search, placement: .sidebar, prompt: "App name or identifier")
            detail
                .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Uninstall")
    }

    @ViewBuilder
    private var detail: some View {
        if let selected, let app = apps.first(where: { $0.id == selected }) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 48, height: 48)
                    VStack(alignment: .leading) {
                        Text(app.name).font(.title2.weight(.semibold))
                        Text(app.bundleID).foregroundStyle(.secondary)
                    }
                }
                Text(app.url.path).font(.caption).foregroundStyle(.secondary)
                if let team = app.teamID { Text("Team \(team)").font(.caption).foregroundStyle(.secondary) }
                if !app.appGroups.isEmpty {
                    Text("App groups: \(app.appGroups.joined(separator: ", "))").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("The list of everything this app owns is the next thing being built.")
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            ContentUnavailableView("Pick an app", systemImage: "trash",
                                   description: Text("Debris will show the app together with its containers, preferences, caches, helpers and receipts, so all of it goes at once."))
        }
    }
}
