import SwiftUI

/// The Watch's Real/Test switch, for when the iPhone is away; the scenario follows the iPhone (TESTING.md §6.5).
struct WatchSettingsView: View {
    @Environment(DataStore.self) private var store
    @State private var pendingMode: DataMode?
    @State private var failure: String?

    var body: some View {
        List {
            Section {
                Toggle("Test Data", isOn: Binding(
                    get: { store.isTestMode },
                    set: { pendingMode = $0 ? .test : .real }
                ))
                .disabled(store.isEphemeral)
                if store.isTestMode {
                    LabeledContent("Scenario", value: store.settings.scenario.title)
                    Button("Reset Test Data") { run { try store.resetTestData() } }
                }
            } footer: {
                Text("Test data never syncs to iCloud and resets whenever the app restarts.")
            }
            if let failure {
                Text(failure).foregroundStyle(.red)
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog(
            pendingMode == .test ? "Use test data?" : "Use real data?",
            isPresented: Binding(get: { pendingMode != nil }, set: {
                if !$0 {
                    pendingMode = nil
                }
            })
        ) {
            Button(pendingMode == .test ? "Use Test Data" : "Use Real Data") {
                if let mode = pendingMode {
                    run { try store.setMode(mode) }
                }
            }
        }
    }

    private func run(_ action: () throws -> Void) {
        do {
            try action()
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
    }
}

#Preview {
    WatchSettingsView()
        .previewStore()
}
