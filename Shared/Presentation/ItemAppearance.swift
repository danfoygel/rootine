import SwiftUI

/// The palette items can be tinted with. Stored on `Item.colorName` by raw value.
enum ItemColor: String, CaseIterable, Identifiable, Sendable {
    case red, orange, yellow, green, mint, teal, cyan, blue, indigo, purple, pink, brown, gray

    var id: Self {
        self
    }

    var color: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .mint: .mint
        case .teal: .teal
        case .cyan: .cyan
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .brown: .brown
        case .gray: .gray
        }
    }

    static func named(_ name: String) -> ItemColor {
        ItemColor(rawValue: name) ?? .blue
    }
}

/// A curated set of SF Symbols for items, chosen for everyday habits and chores.
enum ItemSymbols {
    static let all = [
        "star", "pills", "drop", "cup.and.saucer", "fork.knife", "carrot",
        "figure.walk", "figure.run", "dumbbell", "figure.yoga", "bicycle", "heart",
        "bed.double", "moon.zzz", "sun.max", "brain.head.profile", "book", "pencil",
        "laptopcomputer", "envelope", "phone", "calendar", "clock", "sparkles",
        "cart", "creditcard", "house", "washer", "tshirt", "trash",
        "leaf", "pawprint", "car", "key", "cross.case", "music.note",
        "camera", "gift", "flame", "bolt",
    ]
}

extension ClockTime {
    func date(on day: LocalDay = LocalDay(.now), calendar: Calendar = .current) -> Date {
        let parts = DateComponents(year: day.year, month: day.month, day: day.day, hour: hour, minute: minute)
        return calendar.date(from: parts) ?? .now
    }

    var formatted: String {
        date().formatted(date: .omitted, time: .shortened)
    }
}

extension LocalDay {
    func startDate(calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .now
    }
}

extension TimeOfDay {
    /// Short label for list rows, e.g. "8:00 AM" or "7:00 AM – 9:00 AM"; `nil` for anytime.
    var label: String? {
        switch self {
        case .anytime: nil
        case let .exact(time): time.formatted
        case let .window(start, end): "\(start.formatted) – \(end.formatted)"
        }
    }
}
