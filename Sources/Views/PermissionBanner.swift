import SwiftUI

struct PermissionBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Debris does not have Full Disk Access")
                    .font(.headline)
                Text("Without it, sandboxed app containers, Mail, Safari and cookies stay invisible, and container leftovers cannot be moved to the Trash.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Check Again") { model.refreshPermissions() }
            Button("Open System Settings") { model.openFullDiskAccessSettings() }
                .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(.orange.opacity(0.08))
        .overlay(alignment: .bottom) { Divider() }
    }
}
