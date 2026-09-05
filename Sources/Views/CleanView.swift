import SwiftUI

struct CleanView: View {
    var body: some View {
        ContentUnavailableView("Clean", systemImage: "sparkles",
                               description: Text("Caches, logs, developer artifacts and installer files, each behind a rule that says what it is and why it is safe to remove. Being built."))
            .navigationTitle("Clean")
    }
}
