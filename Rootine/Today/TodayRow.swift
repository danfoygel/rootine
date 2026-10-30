import SwiftUI

/// A dense list row: tapping the text edits the item, tapping the trailing control checks it off or adds a step.
struct TodayRow: View {
    let entry: TodayEntry
    let item: Item
    let isOverdue: Bool
    let record: (Int) -> Void
    let edit: () -> Void

    private var tint: Color {
        ItemColor.named(item.colorName).color
    }

    private var isCounted: Bool {
        entry.plan.kind == .counted
    }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: edit) {
                HStack(spacing: 10) {
                    Image(systemName: item.symbolName)
                        .foregroundStyle(tint)
                        .frame(width: 26)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.plan.name)
                            .foregroundStyle(entry.isDone ? .secondary : .primary)
                            .strikethrough(entry.isDone && !isCounted)
                            .lineLimit(1)
                        if let detail {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(isOverdue ? .red : .secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            control
        }
        .sensoryFeedback(trigger: entry.total) { old, new in
            if new < old {
                return .decrease
            }
            return entry.isDone ? .success : .increase
        }
        .swipeActions(edge: .trailing) {
            if let undo = entry.undoStepAmount {
                Button("Undo", systemImage: "minus") { record(undo) }
                    .tint(.orange)
            }
            Button("Edit", systemImage: "pencil", action: edit)
        }
        .contextMenu {
            Button("Edit", systemImage: "pencil", action: edit)
            if let undo = entry.undoStepAmount {
                Button("Undo Last Step", systemImage: "minus") { record(undo) }
            }
            if let reset = entry.resetAmount {
                Button("Reset Today", systemImage: "arrow.counterclockwise", role: .destructive) { record(reset) }
            }
        }
    }

    /// e.g. "Overdue · 8:00 AM" or "750 / 2,000 ml · 7:00 AM – 9:00 AM".
    private var detail: String? {
        var parts: [String] = []
        if entry.isCarriedOver, let due = entry.plan.dueDay {
            parts.append("Due \(due.startDate().formatted(.dateTime.month(.abbreviated).day()))")
        } else if isOverdue {
            parts.append("Overdue")
        }
        if isCounted {
            let unit = item.unit.isEmpty ? "" : " \(item.unit)"
            parts.append("\(entry.total.formatted()) / \(entry.target.formatted())\(unit)")
        }
        if let time = entry.plan.timeOfDay.label {
            parts.append(time)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var control: some View {
        Button {
            record(entry.tapAmount)
        } label: {
            Group {
                if isCounted {
                    ProgressRing(fraction: Double(entry.total) / Double(entry.target), tint: tint, isDone: entry.isDone)
                } else {
                    Image(systemName: entry.isDone ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(entry.isDone ? tint : .secondary)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(controlLabel)
    }

    private var controlLabel: String {
        if isCounted {
            return "Add \(max(1, entry.plan.stepSize))"
        }
        return entry.isDone ? "Mark not done" : "Mark done"
    }
}

/// Counted-item control: progress ring with a plus (or a check once the target is met).
private struct ProgressRing: View {
    let fraction: Double
    let tint: Color
    let isDone: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.2), lineWidth: 3)
            Circle()
                .trim(from: 0, to: min(1, fraction))
                .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: isDone ? "checkmark" : "plus")
                .font(.caption.bold())
                .foregroundStyle(tint)
        }
        .frame(width: 26, height: 26)
        .animation(.snappy, value: fraction)
    }
}
