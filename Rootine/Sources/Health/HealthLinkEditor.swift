import SwiftUI

/// The editor's Health row in the Data Source section; opens `HealthLinkEditor`.
struct HealthLinkRow: View {
    @Binding var link: ItemLink?
    let kind: ItemKind

    var body: some View {
        NavigationLink {
            HealthLinkEditor(link: $link, kind: kind)
        } label: {
            Label("Health", systemImage: "heart")
        }
        .accessibilityIdentifier("editor.healthLink")
    }
}

/// Picks a Health type and a threshold or per-unit rule, e.g. at least 10,000 steps, or 1 per ml of water.
/// The link applies to the item on Save in the item editor.
struct HealthLinkEditor: View {
    @Binding var link: ItemLink?
    let kind: ItemKind

    @Environment(\.dismiss) private var dismiss
    @State private var choice: HealthChoice
    @State private var rule: HealthChoice.Rule
    @State private var amount: Double
    /// Workouts only; `nil` counts every activity.
    @State private var activity: String?

    init(link: Binding<ItemLink?>, kind: ItemKind) {
        _link = link
        self.kind = kind
        let existing = link.wrappedValue
        let choice = existing.flatMap { HealthChoice.choice(for: $0.metric) } ?? HealthChoice.all[0]
        let entry = existing.flatMap { HealthChoice.choice(for: $0.metric) != nil ? choice.entry(for: $0) : nil }
        _choice = State(initialValue: choice)
        _rule = State(initialValue: entry?.rule ?? choice.defaultRule(for: kind))
        _amount = State(initialValue: entry?.amount ?? choice.defaultAmount)
        _activity = State(initialValue: existing?.subject)
    }

    var body: some View {
        Form {
            Section {
                Picker("Type", selection: $choice) {
                    ForEach(HealthChoice.all) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                if choice.metric == .workouts {
                    Picker("Activity", selection: $activity) {
                        Text("Any").tag(String?.none)
                        ForEach(HealthType.workoutActivities, id: \.self) { name in
                            Text(name).tag(Optional(name))
                        }
                    }
                }
            }
            Section {
                Picker("Rule", selection: $rule) {
                    ForEach(rules) { rule in
                        Text(rule.title).tag(rule)
                    }
                }
                .pickerStyle(.segmented)
                LabeledContent(choice.entryUnit) {
                    TextField("Amount", value: $amount, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("healthLink.amount")
                }
            } footer: {
                Text(footer)
            }
            Section {
                Button("Link to \(choice.title)") {
                    link = choice.link(rule, amount: amount, subject: choice.metric == .workouts ? activity : nil)
                    dismiss()
                }
                .disabled(amount <= 0)
                .accessibilityIdentifier("healthLink.apply")
            }
        }
        .navigationTitle("Health")
        .onAppear {
            if !rules.contains(rule) {
                rule = choice.defaultRule(for: kind)
            }
        }
        .onChange(of: choice) { _, choice in
            rule = choice.defaultRule(for: kind)
            amount = choice.defaultAmount
        }
    }

    /// "1 per" only makes sense for counted items, whose progress is a number.
    private var rules: [HealthChoice.Rule] {
        kind == .counted ? HealthChoice.Rule.allCases : [.atLeast, .atMost]
    }

    private var footer: String {
        switch rule {
        case .atLeast: "Done once the day reaches this."
        case .atMost: "Done while the day stays at or under this."
        case .counts: "Adds 1 to the item for each \(amount.formatted()) \(choice.entryUnit)."
        }
    }
}
