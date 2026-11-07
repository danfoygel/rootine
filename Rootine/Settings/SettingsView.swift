import SwiftUI
import UniformTypeIdentifiers

/// The Real/Test data switch and the tools around it (TESTING.md §6.5–6.7).
struct SettingsView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var pendingMode: DataMode?
    @State private var export: ExportFile?
    @State private var isImporting = false
    @State private var isConfirmingDeleteTestItems = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                LocationSettingsSection()
                testDataSection
                realDataSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                pendingMode == .test ? "Switch to Test Data?" : "Switch to Real Data?",
                isPresented: Binding(get: { pendingMode != nil }, set: {
                    if !$0 {
                        pendingMode = nil
                    }
                }),
                titleVisibility: .visible
            ) {
                Button(pendingMode == .test ? "Use Test Data" : "Use Real Data") {
                    if let mode = pendingMode {
                        run { try store.setMode(mode) }
                    }
                }
                .accessibilityIdentifier("settings.confirmMode")
            } message: {
                Text(pendingMode == .test ? switchToTestMessage : switchToRealMessage)
            }
            .confirmationDialog(
                "Delete items named “TEST …”?",
                isPresented: $isConfirmingDeleteTestItems,
                titleVisibility: .visible
            ) {
                Button("Delete TEST Items", role: .destructive) {
                    run {
                        let count = try store.deleteTestItems()
                        message = count == 1 ? "Deleted 1 item." : "Deleted \(count) items."
                    }
                }
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
                run { try load(result.get()) }
            }
            .alert("Settings", isPresented: Binding(get: { message != nil }, set: {
                if !$0 {
                    message = nil
                }
            })) {
                Button("OK") { message = nil }
            } message: {
                Text(message ?? "")
            }
        }
    }

    private var switchToTestMessage: String {
        "Shows the \(store.settings.scenario.title) scenario on this iPhone and the Watch. " +
            "Your real data isn't touched, and test data resets on every restart."
    }

    private var switchToRealMessage: String {
        "Goes back to your real data on this iPhone and the Watch. Test changes are discarded."
    }

    private var testDataSection: some View {
        Section {
            Toggle("Use Test Data", isOn: Binding(
                get: { store.isTestMode },
                set: { pendingMode = $0 ? .test : .real }
            ))
            .disabled(store.isEphemeral)
            .accessibilityIdentifier("settings.testModeToggle")
            Picker("Scenario", selection: Binding(
                get: { store.settings.scenario },
                set: { scenario in run { try store.choose(scenario) } }
            )) {
                ForEach(Scenario.allCases) { scenario in
                    Text(scenario.title).tag(scenario)
                }
            }
            .disabled(store.isEphemeral)
            Button("Reset Test Data") {
                run { try store.resetTestData() }
            }
            .disabled(!store.isTestMode)
            Button("Load Export into Test Data…") { isImporting = true }
                .disabled(!store.isTestMode)
        } header: {
            Text("Test Data")
        } footer: {
            Text("Test data is kept apart from your real data and never syncs to iCloud. Change it freely: " +
                "it goes back to the scenario whenever the app restarts, and the Watch follows.")
        }
    }

    private var realDataSection: some View {
        Section {
            if let export {
                ShareLink("Share Export", item: export.url)
            } else {
                Button("Export Real Data") {
                    run {
                        let data = try store.exportRealData()
                        let url = FileManager.default.temporaryDirectory.appending(path: data.suggestedFileName)
                        try data.encoded().write(to: url)
                        export = ExportFile(url: url)
                    }
                }
            }
            Button("Delete TEST Items…", role: .destructive) { isConfirmingDeleteTestItems = true }
                .disabled(store.isTestMode || store.isEphemeral)
        } header: {
            Text("Real Data")
        } footer: {
            Text("Exports are for reproducing bugs in test data; keep them out of the repository. " +
                "Items named “TEST …” are for checking sync on the real store.")
        }
    }

    private func load(_ url: URL) throws {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isScoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        try store.loadIntoTestData(DataExport.decode(Data(contentsOf: url)))
    }

    private func run(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            message = error.localizedDescription
        }
    }
}

private struct ExportFile {
    var url: URL
}

#Preview {
    SettingsView()
        .previewStore()
}
