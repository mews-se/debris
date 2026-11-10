import AppKit
import DebrisKit
import SwiftUI

struct RemovalResultsSheet: View {
    let results: [RemovalResult]
    let dismiss: () -> Void

    private var succeeded: [RemovalResult] { results.filter(\.succeeded) }
    private var failed: [RemovalResult] { results.filter { !$0.succeeded } }
    private var movedSize: Int64 { succeeded.reduce(0) { $0 + ($1.size ?? 0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2.weight(.semibold))
            if !succeeded.isEmpty {
                Text("The space comes back when you empty the Trash. Until then a mistake is one drag away from undone.")
                    .foregroundStyle(.secondary)
            }
            List {
                if !failed.isEmpty {
                    Section("Could not move") {
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
                Section("Moved") {
                    ForEach(succeeded) { result in
                        HStack {
                            Text(result.url.path).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(Format.size(result.size)).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
            }
            HStack {
                if !succeeded.isEmpty, let trash = FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first {
                    Button("Show Trash") { NSWorkspace.shared.open(trash) }
                }
                Spacer()
                Button("Done", action: dismiss).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 640, height: 460)
    }

    private var title: String {
        let size = movedSize > 0 ? " (\(Format.size(movedSize)))" : ""
        return failed.isEmpty
            ? "Moved \(succeeded.count) items\(size) to the Trash"
            : "Moved \(succeeded.count) items\(size), \(failed.count) failed"
    }
}
