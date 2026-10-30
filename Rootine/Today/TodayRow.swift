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
                        if let detail = entry.detail(unit: item.unit, isOverdue: isOverdue) {
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
