import DebrisKit
import SwiftUI

/// One file or folder in a removal list, shared by the Leftovers and Uninstall modules.
struct ItemRow: View {
    let item: LeftoverItem
    let isSelected: Bool
    let onToggle: (Bool) -> Void
    var showLocation = true

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { isSelected }, set: onToggle))
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
            if showLocation {
                Text(item.location.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 150, alignment: .leading)
            }
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
