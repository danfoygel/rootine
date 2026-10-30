import Foundation

/// The event amounts a list interaction records. Undo is always a negative event, never a deletion.
extension TodayEntry {
    private var step: Int {
        max(1, plan.stepSize)
    }

    /// The primary tap: check off or un-check a habit or to-do, or add one step to a counted item.
    /// Un-checking cancels the whole day's total, which can be more than 1 if two devices both checked it.
    var tapAmount: Int {
        if plan.kind == .counted {
            return step
        }
        return isDone ? -total : 1
    }

    /// Takes back the last counted step; `nil` when there is nothing to take back.
    var undoStepAmount: Int? {
        guard plan.kind == .counted, total > 0 else { return nil }
        return -min(step, total)
    }

    /// Clears a counted item's progress for the day; `nil` when there is nothing to clear.
    var resetAmount: Int? {
        guard plan.kind == .counted, total > 0 else { return nil }
        return -total
    }
}
