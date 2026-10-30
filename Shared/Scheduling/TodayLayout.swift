import Foundation

/// The switchable layouts for today's list (section 13 of the requirements).
enum TodayLayout: String, CaseIterable, Identifiable, Sendable {
    case byTime
    case byCategory
    case byUrgency

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .byTime: "Time of Day"
        case .byCategory: "Category"
        case .byUrgency: "Urgency"
        }
    }

    var symbolName: String {
        switch self {
        case .byTime: "clock"
        case .byCategory: "folder"
        case .byUrgency: "list.bullet"
        }
    }

    func sections(for entries: [TodayEntry], at now: ClockTime) -> [TodaySection] {
        switch self {
        case .byTime: timeSections(entries)
        case .byCategory: categorySections(entries, at: now)
        case .byUrgency:
            entries.isEmpty ? [] : [TodaySection(id: "all", title: nil, entries: entries.sortedByUrgency(at: now))]
        }
    }

    private func timeSections(_ entries: [TodayEntry]) -> [TodaySection] {
        let ordered = entries.sorted { lhs, rhs in
            let lhsTime = lhs.plan.timeOfDay.reminderTime?.minutesSinceMidnight ?? .max
            let rhsTime = rhs.plan.timeOfDay.reminderTime?.minutesSinceMidnight ?? .max
            if lhsTime != rhsTime {
                return lhsTime < rhsTime
            }
            return lhs.plan.name.localizedStandardCompare(rhs.plan.name) == .orderedAscending
        }
        let grouped = Dictionary(grouping: ordered) { PartOfDay($0.plan.timeOfDay.reminderTime) }
        return PartOfDay.allCases.compactMap { part in
            grouped[part].map { TodaySection(id: part.rawValue, title: part.title, entries: $0) }
        }
    }

    private func categorySections(_ entries: [TodayEntry], at now: ClockTime) -> [TodaySection] {
        let grouped = Dictionary(grouping: entries) { $0.plan.category?.id }
        let categories = grouped.keys.compactMap { id in id.flatMap { grouped[$0]?.first?.plan.category } }
            .sorted { lhs, rhs in
                if lhs.sortOrder != rhs.sortOrder {
                    return lhs.sortOrder < rhs.sortOrder
                }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        var sections = categories.map { category in
            TodaySection(
                id: category.id.uuidString,
                title: category.name,
                entries: (grouped[category.id] ?? []).sortedByUrgency(at: now)
            )
        }
        if let uncategorized = grouped[nil] {
            sections.append(TodaySection(id: "none", title: "Other", entries: uncategorized.sortedByUrgency(at: now)))
        }
        return sections
    }
}

struct TodaySection: Identifiable, Hashable, Sendable {
    var id: String
    /// `nil` for a single untitled section.
    var title: String?
    var entries: [TodayEntry]
}

/// Buckets for the "Time of Day" layout, by when an item's reminder would fire.
private enum PartOfDay: String, CaseIterable {
    case morning
    case afternoon
    case evening
    case anytime

    init(_ time: ClockTime?) {
        switch time?.hour {
        case nil: self = .anytime
        case let hour? where hour < 12: self = .morning
        case let hour? where hour < 17: self = .afternoon
        default: self = .evening
        }
    }

    var title: String {
        switch self {
        case .morning: "Morning"
        case .afternoon: "Afternoon"
        case .evening: "Evening"
        case .anytime: "Anytime"
        }
    }
}
