import SwiftData
import SwiftUI

/// Today's list on the Watch: one flat list in urgency order, check off or log taps, quick-add to-dos.
/// Creating and editing recurring items happens on the iPhone.
struct WatchTodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(WatchRelay.self) private var relay
    @Environment(DataStore.self) private var store
    @Environment(\.appClock) private var clock
    @Query private var items: [Item]
    @Query private var events: [CompletionEvent]
    @State private var isShowingSettings = false

    var body: some View {
        NavigationStack {
            TimelineView(.everyMinute) { context in
                list(at: clock.now(context.date))
            }
            .navigationTitle(store.isTestMode ? "Test Data" : "Today")
            .sheet(isPresented: $isShowingSettings) {
                WatchSettingsView()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Settings", systemImage: store.isTestMode ? "flask" : "gearshape") {
                        isShowingSettings = true
                    }
                    .tint(store.isTestMode ? .orange : nil)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    TextFieldLink(prompt: Text("New to-do")) {
                        Label("Add To-do", systemImage: "plus")
                    } onSubmit: { text in
                        addToDo(named: text)
                    }
                }
            }
        }
        .relaying(items: items, events: events, through: relay, today: clock.today)
    }

    private func list(at date: Date) -> some View {
        let day = LocalDay(date)
        let now = ClockTime(date)
        let today = TodayData(on: day, items: items, events: events, relay: relay.state)
        let entries = today.entries.sortedByUrgency(at: now)
        let remaining = entries.count { !$0.isDone }

        return List {
            if !entries.isEmpty {
                Section {
                    ForEach(entries) { entry in
                        if let item = today.itemsByID[entry.id] {
                            WatchTodayRow(
                                entry: entry,
                                item: item,
                                isOverdue: entry.isOverdue(at: now),
                                record: { amount in
                                    if let record = modelContext.recordProgress(amount, itemID: entry.id, on: day) {
                                        relay.send(record)
                                    }
                                }
                            )
                        }
                    }
                } header: {
                    Text(remaining == 0 ? "All done" : "\(remaining) left")
                }
            }
        }
        .overlay {
            if entries.isEmpty {
                ContentUnavailableView(
                    "Nothing Today",
                    systemImage: "leaf",
                    description: Text("Tap + to add a to-do.")
                )
            }
        }
        .onChange(of: TodayGlance(today, on: day, at: now, isTestData: store.isTestMode), initial: true) { _, glance in
            glance.publish()
        }
    }

    private func addToDo(named text: String) {
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        modelContext.insert(Item(name: name, kind: .oneOff, startDay: clock.today))
    }
}

#Preview {
    WatchTodayView()
        .previewStore()
}
