import SwiftData
import SwiftUI

/// Today's list on the Watch: one flat list in urgency order, check off or log taps, quick-add to-dos.
/// Creating and editing recurring items happens on the iPhone.
struct WatchTodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [Item]
    @Query private var events: [CompletionEvent]

    var body: some View {
        NavigationStack {
            TimelineView(.everyMinute) { context in
                list(at: context.date)
            }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    TextFieldLink(prompt: Text("New to-do")) {
                        Label("Add To-do", systemImage: "plus")
                    } onSubmit: { text in
                        addToDo(named: text)
                    }
                }
            }
        }
    }

    private func list(at date: Date) -> some View {
        let day = LocalDay(date)
        let now = ClockTime(date)
        let entries = DayPlanner().entries(on: day, items: items, events: events).sortedByUrgency(at: now)
        // CloudKit can't enforce unique IDs, so tolerate duplicates rather than trapping.
        let itemsByID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let remaining = entries.count { !$0.isDone }

        return List {
            if !entries.isEmpty {
                Section {
                    ForEach(entries) { entry in
                        if let item = itemsByID[entry.id] {
                            WatchTodayRow(
                                entry: entry,
                                item: item,
                                isOverdue: entry.isOverdue(at: now),
                                record: { modelContext.recordProgress($0, itemID: entry.id, on: day) }
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
    }

    private func addToDo(named text: String) {
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        modelContext.insert(Item(name: name, kind: .oneOff))
    }
}

#Preview {
    WatchTodayView()
        .modelContainer(PreviewData.container())
}
