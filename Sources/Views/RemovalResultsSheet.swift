import AppKit
import DebrisKit
import SwiftUI

struct RemovalResultsSheet: View {
    let results: [RemovalResult]
    let dismiss: () -> Void

    private var moved: [RemovalResult] { results.filter { $0.succeeded && !$0.wasDeleted } }
    private var deleted: [RemovalResult] { results.filter(\.wasDeleted) }
    private var failed: [RemovalResult] { results.filter { !$0.succeeded } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2.weight(.semibold))
            if !moved.isEmpty {
                Text("The space comes back when you empty the Trash. Until then a mistake is one drag away from undone.")
                    .foregroundStyle(.secondary)
            }
            if !deleted.isEmpty {
                Text("Simulator runtimes were deleted right away, \(Format.size(total(deleted))) in all.")
                    .foregroundStyle(.secondary)
            }
            List {
                if !failed.isEmpty {
                    Section("Could not remove") {
                        ForEach(failed) { result in
                            VStack(alignment: .leading) {
                                Text(result.url.path).lineLimit(1).truncationMode(.middle)
                                if case .failed(let message) = result.outcome {
                                    Text(message).font(.caption).foregroundStyle(.red)
                                }
                            }
                        }
                    }
                }
                if !moved.isEmpty {
                    Section("Moved to the Trash") {
                        ForEach(moved) { row($0) }
                    }
                }
                if !deleted.isEmpty {
                    Section("Deleted") {
                        ForEach(deleted) { row($0) }
                    }
                }
            }
            HStack {
                if !moved.isEmpty, let trash = FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first {
                    Button("Show Trash") { NSWorkspace.shared.open(trash) }
                }
                Spacer()
                Button("Done", action: dismiss).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 640, height: 460)
    }

    private func row(_ result: RemovalResult) -> some View {
        HStack {
            Text(result.url.path).lineLimit(1).truncationMode(.middle)
            Spacer()
            Text(Format.size(result.size)).monospacedDigit().foregroundStyle(.secondary)
        }
    }

    private func total(_ results: [RemovalResult]) -> Int64 {
        results.reduce(0) { $0 + ($1.size ?? 0) }
    }

    private var title: String {
        let size = total(moved)
        let sized = size > 0 ? " (\(Format.size(size)))" : ""
        let failures = failed.isEmpty ? "" : ", \(failed.count) failed"
        if deleted.isEmpty {
            return failed.isEmpty
                ? "Moved \(moved.count) items\(sized) to the Trash"
                : "Moved \(moved.count) items\(sized)\(failures)"
        }
        if moved.isEmpty { return "Deleted \(deleted.count) simulator runtimes\(failures)" }
        return "Moved \(moved.count) items\(sized) to the Trash and deleted \(deleted.count)\(failures)"
    }
}
