import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(WatchRelay.self) private var relay
    @Query private var items: [Item]
    @Query private var events: [CompletionEvent]
    @AppStorage("todayLayout") private var layout = TodayLayout.byTime
    @State private var editorTarget: EditorTarget?

    var body: some View {
        NavigationStack {
            // Re-evaluates each minute so overdue state and the day itself roll over without a relaunch.
            TimelineView(.everyMinute) { context in
                list(at: context.date)
            }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    layoutMenu
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Item", systemImage: "plus") { editorTarget = .new }
                }
            }
            .sheet(item: $editorTarget) { target in
                ItemEditorView(item: target.item)
            }
        }
        .relaying(items: items, events: events, through: relay)
    }

    private func list(at date: Date) -> some View {
        let day = LocalDay(date)
        let now = ClockTime(date)
        let today = TodayData(on: day, items: items, events: events, relay: relay.state)
        let entries = today.entries
        // CloudKit can't enforce unique IDs, so tolerate duplicates rather than trapping.
        let modelsByID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let doneCount = entries.count(where: \.isDone)

        return List {
            ForEach(layout.sections(for: entries, at: now)) { section in
                Section {
                    ForEach(section.entries) { entry in
                        if let item = today.itemsByID[entry.id] {
                            TodayRow(
                                entry: entry,
                                item: item,
                                isOverdue: entry.isOverdue(at: now),
                                record: { record($0, for: entry, on: day) },
                                edit: modelsByID[entry.id].map { model in { editorTarget = .edit(model) } }
                            )
                        }
                    }
                } header: {
                    if let title = section.title {
                        Text(title)
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationSubtitle(
            "\(date.formatted(.dateTime.weekday(.wide).month().day())) · \(doneCount) of \(entries.count) done"
        )
        .overlay {
            if entries.isEmpty {
                emptyState
            }
        }
    }

    private func record(_ amount: Int, for entry: TodayEntry, on day: LocalDay) {
        if let record = modelContext.recordProgress(amount, itemID: entry.id, on: day) {
            relay.send(record)
        }
    }

    private var layoutMenu: some View {
        Menu {
            Picker("Layout", selection: $layout) {
                ForEach(TodayLayout.allCases) { layout in
                    Label(layout.title, systemImage: layout.symbolName).tag(layout)
                }
            }
        } label: {
            Label("Layout", systemImage: layout.symbolName)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(items.isEmpty ? "No Items Yet" : "Nothing Today", systemImage: "leaf")
        } description: {
            Text(items.isEmpty ? "Add a habit, to-do or counted item." : "Nothing is scheduled for today.")
        } actions: {
            if items.isEmpty {
                Button("Add Item") { editorTarget = .new }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

private enum EditorTarget: Identifiable {
    case new
    case edit(Item)

    var id: String {
        switch self {
        case .new: "new"
        case let .edit(item): item.id.uuidString
        }
    }

    var item: Item? {
        switch self {
        case .new: nil
        case let .edit(item): item
        }
    }
}

#Preview {
    TodayView()
        .modelContainer(PreviewData.container())
        .environment(WatchRelay.inert)
}
