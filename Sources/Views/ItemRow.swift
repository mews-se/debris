import DebrisKit
import SwiftUI

/// One file or folder in a removal list, shared by all three modules.
struct ItemRow: View {
    let item: LeftoverItem
    let isSelected: Bool
    let onToggle: (Bool) -> Void
    var showLocation = true
    var badge: String?

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { isSelected }, set: onToggle))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(!item.isRemovable)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).lineLimit(1).truncationMode(.middle)
                Text(Format.homeRelative(item.url))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if let badge {
                Text(badge)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.green.opacity(0.15), in: Capsule())
                    .foregroundStyle(.green)
            }
            if let reason = item.blockedReason {
                Label("Cannot be moved", systemImage: "hand.raised")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(reason)
            } else if item.requiresAdmin {
                Image(systemName: "lock").foregroundStyle(.secondary)
                    .help("Owned by the system; macOS asks for an administrator password when it is moved")
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

/// Checkbox for a whole section: on, off, or a dash when only some rows are selected.
struct SelectionCheckbox: View {
    let state: Bool?
    let onToggle: (Bool) -> Void

    var body: some View {
        Button {
            onToggle(state != true)
        } label: {
            Image(systemName: state == true ? "checkmark.square.fill" : state == nil ? "minus.square.fill" : "square")
                .foregroundStyle(state == false ? .secondary : Color.accentColor)
        }
        .buttonStyle(.plain)
    }
}

struct ScanProgressBar: View {
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
