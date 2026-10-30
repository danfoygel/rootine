import SwiftUI

/// The whole row is the tap target: it checks off a habit or to-do, or adds a step to a counted item.
/// Swipe to take back a counted step.
struct WatchTodayRow: View {
    let entry: TodayEntry
    let item: Item
    let isOverdue: Bool
    let record: (Int) -> Void

    private var tint: Color {
        ItemColor.named(item.colorName).color
    }

    private var isCounted: Bool {
        entry.plan.kind == .counted
    }

    var body: some View {
        Button {
            record(entry.tapAmount)
        } label: {
            HStack(spacing: 10) {
                status
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.plan.name)
                        .foregroundStyle(entry.isDone ? .secondary : .primary)
                        .strikethrough(entry.isDone && !isCounted)
                        .lineLimit(2)
                    if let detail = entry.detail(unit: item.unit, isOverdue: isOverdue) {
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(isOverdue ? .red : .secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .sensoryFeedback(trigger: entry.total) { old, new in
            if new < old {
                return .decrease
            }
            return entry.isDone ? .success : .increase
        }
        .swipeActions {
            if let undo = entry.undoStepAmount {
                Button("Undo", systemImage: "minus") { record(undo) }
                    .tint(.orange)
            }
        }
        .accessibilityHint(accessibilityHint)
    }

    @ViewBuilder private var status: some View {
        if isCounted {
            ProgressRing(
                fraction: Double(entry.total) / Double(entry.target),
                tint: tint,
                isDone: entry.isDone,
                size: 24
            )
        } else {
            Image(systemName: entry.isDone ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(entry.isDone ? tint : tint.opacity(0.7))
        }
    }

    private var accessibilityHint: String {
        if isCounted {
            return "Adds \(max(1, entry.plan.stepSize))"
        }
        return entry.isDone ? "Marks not done" : "Marks done"
    }
}
