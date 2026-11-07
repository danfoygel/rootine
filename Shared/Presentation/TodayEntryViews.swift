import SwiftUI

extension TodayEntry {
    /// Secondary line for list rows, e.g. "Overdue · 8:00 AM" or "750 / 2,000 ml · 7:00 AM – 9:00 AM".
    /// `reading` is the linked reading's label, e.g. "52m of 1h" (`readingLabel(from:)`).
    func detail(unit: String, isOverdue: Bool, reading: String? = nil) -> String? {
        var parts: [String] = []
        if isCarriedOver, let due = plan.dueDay {
            parts.append("Due \(due.startDate().formatted(.dateTime.month(.abbreviated).day()))")
        } else if isOverdue {
            parts.append("Overdue")
        }
        if plan.kind == .counted {
            let unitSuffix = unit.isEmpty ? "" : " \(unit)"
            parts.append("\(total.formatted()) / \(target.formatted())\(unitSuffix)")
        }
        if let reading {
            parts.append(reading)
        }
        if let time = plan.timeOfDay.label {
            parts.append(time)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Counted-item control: progress ring with a plus (or a check once the target is met).
struct ProgressRing: View {
    let fraction: Double
    let tint: Color
    let isDone: Bool
    var size: CGFloat = 26

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
        .frame(width: size, height: size)
        .animation(.snappy, value: fraction)
    }
}
