import DebrisKit
import SwiftUI

struct RemovalResultsSheet: View {
    let results: [RemovalResult]
    let dismiss: () -> Void

    private var succeeded: [RemovalResult] { results.filter(\.succeeded) }
    private var failed: [RemovalResult] { results.filter { !$0.succeeded } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(failed.isEmpty ? "Moved \(succeeded.count) items to the Trash" : "Moved \(succeeded.count) items, \(failed.count) failed")
                .font(.title2.weight(.semibold))
            Text("Everything is in the Trash until you empty it, so a mistake is one drag away from undone.")
                .foregroundStyle(.secondary)
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
                        Text(result.url.path).lineLimit(1).truncationMode(.middle)
                    }
                }
            }
            HStack {
                Spacer()
                Button("Done", action: dismiss).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 640, height: 460)
    }
}
