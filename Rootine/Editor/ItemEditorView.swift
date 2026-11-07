import SwiftData
import SwiftUI

/// Creates a new item (`item == nil`) or edits an existing one. Changes apply only on Save.
struct ItemEditorView: View {
    let item: Item?
    let today: LocalDay

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(WatchRelay.self) private var relay
    @Query(sort: [SortDescriptor(\ItemCategory.sortOrder), SortDescriptor(\ItemCategory.name)])
    private var categories: [ItemCategory]
    @State private var draft: ItemDraft
    @State private var isAddingCategory = false
    @State private var newCategoryName = ""
    @State private var isConfirmingDelete = false

    init(item: Item?, today: LocalDay) {
        self.item = item
        self.today = today
        _draft = State(initialValue: item.map { ItemDraft(item: $0, today: today) } ?? ItemDraft(today: today))
    }

    var body: some View {
        NavigationStack {
            Form {
                basicsSection
                if draft.kind == .counted {
                    targetSection
                }
                if draft.kind == .oneOff {
                    dueSection
                } else {
                    scheduleSection
                }
                timeSection
                dataSourceSection
                if item != nil {
                    deleteSection
                }
            }
            .navigationTitle(item == nil ? "New Item" : "Edit Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(draft.problem != nil)
                        .accessibilityIdentifier("editor.save")
                }
            }
            .alert("New Category", isPresented: $isAddingCategory) {
                TextField("Name", text: $newCategoryName)
                Button("Add", action: addCategory)
                Button("Cancel", role: .cancel) { newCategoryName = "" }
            }
            .confirmationDialog(
                "Delete “\(draft.trimmedName)”?",
                isPresented: $isConfirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete Item", role: .destructive, action: delete)
                    .accessibilityIdentifier("editor.confirmDelete")
            } message: {
                Text("Its completion history is deleted too.")
            }
        }
    }

    private var basicsSection: some View {
        Section {
            TextField("Name", text: $draft.name)
                .accessibilityIdentifier("editor.name")
            Picker("Type", selection: $draft.kind) {
                Text("Habit").tag(ItemKind.habit)
                Text("To-do").tag(ItemKind.oneOff)
                Text("Counted").tag(ItemKind.counted)
            }
            .pickerStyle(.segmented)
            NavigationLink {
                AppearancePicker(symbolName: $draft.symbolName, colorName: $draft.colorName)
            } label: {
                LabeledContent("Icon") {
                    Image(systemName: draft.symbolName)
                        .foregroundStyle(ItemColor.named(draft.colorName).color)
                }
            }
            Picker("Category", selection: $draft.categoryID) {
                Text("None").tag(UUID?.none)
                ForEach(categories) { category in
                    Text(category.name).tag(Optional(category.id))
                }
            }
            Button("New Category…") { isAddingCategory = true }
        } footer: {
            // Hide the empty-name nag until the user has started typing.
            if let problem = draft.problem, !draft.trimmedName.isEmpty {
                Text(problem).foregroundStyle(.red)
            }
        }
    }

    private var targetSection: some View {
        Section("Daily Target") {
            TextField("Unit (e.g. glasses, ml)", text: $draft.unit)
            numberField("Target", value: $draft.dailyTarget)
            numberField("Each tap adds", value: $draft.stepSize)
        }
    }

    private var dueSection: some View {
        Section {
            Toggle("Due Date", isOn: $draft.hasDueDay.animation())
            if draft.hasDueDay {
                DatePicker("Due", selection: $draft.dueDate, displayedComponents: .date)
            }
        } footer: {
            Text("Stays on today's list until it's done.")
        }
    }

    private var scheduleSection: some View {
        Section {
            Picker("Repeats", selection: $draft.pattern) {
                ForEach(ItemDraft.Pattern.allCases) { pattern in
                    Text(pattern.title).tag(pattern)
                }
            }
            patternControls
            DatePicker(
                draft.pattern == .daysAfterLastDone ? "First Due" : "Starts",
                selection: $draft.startDate,
                displayedComponents: .date
            )
        } header: {
            Text("Schedule")
        } footer: {
            if draft.pattern == .monthly, !draft.monthlyOnLastDay, draft.monthDay > 28 {
                Text("Shorter months use their last day.")
            }
        }
    }

    @ViewBuilder private var patternControls: some View {
        switch draft.pattern {
        case .daily:
            EmptyView()
        case .everyNDays:
            Stepper("Every \(draft.everyNDays) days", value: $draft.everyNDays, in: 2 ... 365)
        case .weekly:
            WeekdayPicker(selection: $draft.weekdays)
        case .monthly:
            Toggle("Last Day of Month", isOn: $draft.monthlyOnLastDay)
            if !draft.monthlyOnLastDay {
                Stepper("On day \(draft.monthDay)", value: $draft.monthDay, in: 1 ... 31)
            }
            Stepper(
                draft.everyMonths == 1 ? "Every month" : "Every \(draft.everyMonths) months",
                value: $draft.everyMonths,
                in: 1 ... 12
            )
        case .timesPerWeek:
            Stepper("\(draft.timesPerWeek) times a week", value: $draft.timesPerWeek, in: 1 ... 7)
        case .daysAfterLastDone:
            Stepper("\(draft.daysAfterLastDone) days after last done", value: $draft.daysAfterLastDone, in: 1 ... 365)
        }
    }

    private var timeSection: some View {
        Section("Time") {
            Picker("Time", selection: $draft.timeMode) {
                ForEach(ItemDraft.TimeMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            switch draft.timeMode {
            case .anytime:
                EmptyView()
            case .exact:
                DatePicker("At", selection: $draft.exactDate, displayedComponents: .hourAndMinute)
            case .window:
                DatePicker("From", selection: $draft.windowStartDate, displayedComponents: .hourAndMinute)
                DatePicker("Until", selection: $draft.windowEndDate, displayedComponents: .hourAndMinute)
            }
        }
    }

    private var dataSourceSection: some View {
        Section {
            if let link = draft.link, link.placeID == nil {
                LabeledContent("Linked to", value: link.summary)
            }
            PlaceLinkRow(link: $draft.link, kind: draft.kind)
            if draft.link != nil {
                Button("Remove Link", role: .destructive) { draft.link = nil }
            }
        } header: {
            Text("Data Source")
        } footer: {
            Text(draft.link == nil
                ? "Link a data source and the item completes on its own."
                : "Completes on its own from readings. Removing the link keeps today's progress.")
        }
    }

    private var deleteSection: some View {
        Section {
            Button("Delete Item", role: .destructive) { isConfirmingDelete = true }
                .accessibilityIdentifier("editor.delete")
        }
    }

    private func numberField(_ title: String, value: Binding<Int>) -> some View {
        LabeledContent(title) {
            TextField(title, value: value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
        }
    }

    private func save() {
        let target = item ?? {
            let newItem = Item(name: draft.trimmedName, kind: draft.kind, startDay: draft.startDay)
            modelContext.insert(newItem)
            return newItem
        }()
        draft.apply(to: target, category: categories.first { $0.id == draft.categoryID })
        if draft.link != nil {
            // A new or changed link picks up readings that are already here.
            for record in (try? modelContext.evaluateLinkedItems(on: today)) ?? [] {
                relay.send(record)
            }
        }
        dismiss()
    }

    private func addCategory() {
        let name = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        newCategoryName = ""
        guard !name.isEmpty else { return }
        let category = ItemCategory(name: name, sortOrder: (categories.map(\.sortOrder).max() ?? -1) + 1)
        modelContext.insert(category)
        draft.categoryID = category.id
    }

    private func delete() {
        if let item {
            relay.noteDeleted(item.id)
            try? modelContext.deleteItem(item)
        }
        dismiss()
    }
}

/// `Date` views of the draft's day and time fields, for `DatePicker`.
private extension ItemDraft {
    var startDate: Date {
        get { startDay.startDate() }
        set { startDay = LocalDay(newValue) }
    }

    var dueDate: Date {
        get { dueDay.startDate() }
        set { dueDay = LocalDay(newValue) }
    }

    var exactDate: Date {
        get { exactTime.date() }
        set { exactTime = ClockTime(newValue) }
    }

    var windowStartDate: Date {
        get { windowStart.date() }
        set { windowStart = ClockTime(newValue) }
    }

    var windowEndDate: Date {
        get { windowEnd.date() }
        set { windowEnd = ClockTime(newValue) }
    }
}

#Preview("New") {
    ItemEditorView(item: nil, today: LocalDay(.now))
        .previewStore()
}
