import Foundation

extension ReadingSource {
    /// The iOS 26 Shortcuts action "Get App & Website Activity", through `LogScreenTimeIntent` (DATA.md §1).
    static let screenTime = ReadingSource(rawValue: "screenTime")
}

extension ReadingMetric {
    /// Seconds in an app in a day. The subject is the app's name as Screen Time shows it.
    static let screenTime = ReadingMetric(rawValue: "screenTime")
    /// Seconds on a website in a day. The subject is its domain. Kept apart from apps, because Safari's app
    /// time already includes its websites.
    static let websiteTime = ReadingMetric(rawValue: "websiteTime")
}

/// One day of Screen Time from the Shortcuts action: seconds per app and per website.
///
/// Built from the text the shortcut hands `LogScreenTimeIntent`: JSON rows of `{app, website, duration}`
/// (one array, one object, or one object per line), or the action's own text form, one `Name (1h 35m)` per
/// line. `duration` may be seconds or text like `1h 2m 3s`; without it, a `description` field is parsed.
struct ScreenTimeReport: Equatable, Sendable {
    enum Kind: Sendable {
        case app
        case website

        var metric: ReadingMetric {
            switch self {
            case .app: .screenTime
            case .website: .websiteTime
            }
        }
    }

    struct Row: Equatable, Sendable {
        var kind: Kind
        var name: String
        var seconds: Double
    }

    /// Seconds per app name. An app listed twice is added up.
    private(set) var apps: [String: Double] = [:]
    /// Seconds per domain.
    private(set) var websites: [String: Double] = [:]
    /// Rows with no name or no readable duration.
    private(set) var skipped = 0

    /// `apps` and `websites` are the results of the action's two runs (Type = Apps, then Websites). A JSON row
    /// that names its website (or app) goes there whichever text it came in.
    init(apps: String? = nil, websites: String? = nil) {
        for (text, kind) in [(apps, Kind.app), (websites, Kind.website)] {
            guard let text else { continue }
            for element in Self.elements(in: text) {
                guard let row = Self.row(from: element, defaultKind: kind) else {
                    skipped += 1
                    continue
                }
                switch row.kind {
                case .app: self.apps[row.name, default: 0] += row.seconds
                case .website: self.websites[row.name, default: 0] += row.seconds
                }
            }
        }
    }

    var isEmpty: Bool {
        apps.isEmpty && websites.isEmpty
    }

    /// One reading per app and per website for `day`.
    ///
    /// Screen Time leaves out apps that weren't used, but "no reading" never counts as zero (`ItemLink`). So a
    /// linked app or site that is missing gets a zero reading, as long as that run (apps or websites) returned
    /// anything at all: an empty run more likely means it failed than that nothing was used.
    func readings(on day: LocalDay, linkedTo links: [ItemLink] = [], calendar: Calendar = .current) -> [ReadingValue] {
        let start = day.startDate(calendar: calendar)
        let end = day.adding(days: 1).startDate(calendar: calendar)
        var readings: [ReadingValue] = []
        for (kind, seconds) in [(Kind.app, apps), (Kind.website, websites)] where !seconds.isEmpty {
            var seconds = seconds
            for link in links where link.metric == kind.metric {
                if let subject = link.subject, seconds[subject] == nil {
                    seconds[subject] = 0
                }
            }
            readings += seconds.sorted { $0.key < $1.key }.map { name, value in
                ReadingValue(source: .screenTime, metric: kind.metric, subject: name, day: day, start: start,
                             end: end, value: value)
            }
        }
        return readings
    }

    // MARK: Parsing

    /// The rows in `text`: a JSON array or object, else one JSON object or text row per line.
    static func elements(in text: String) -> [Any] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if let json = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8), options: .fragmentsAllowed) {
            return json as? [Any] ?? [json]
        }
        return trimmed.split(whereSeparator: \.isNewline).compactMap { line in
            let line = line.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { return nil }
            return (try? JSONSerialization.jsonObject(with: Data(line.utf8))) ?? line
        }
    }

    /// A row from a JSON object (keys in any case) or a `Name (1h 35m)` string; `nil` if it isn't one.
    static func row(from element: Any, defaultKind: Kind) -> Row? {
        if let text = element as? String {
            return described(text).map { Row(kind: defaultKind, name: $0.name, seconds: $0.seconds) }
        }
        guard let object = element as? [String: Any] else { return nil }
        let fields = Dictionary(object.map { ($0.key.lowercased(), $0.value) }) { first, _ in first }
        let website = name(fields["website"])
        let app = name(fields["app"])
        let description = (fields["description"] as? String).flatMap(described)
        let kind: Kind = website != nil ? .website : app != nil ? .app : defaultKind
        guard let name = website ?? app ?? description?.name,
              let seconds = duration(fields["duration"]) ?? description?.seconds else { return nil }
        return Row(kind: kind, name: name, seconds: seconds)
    }

    private static func name(_ value: Any?) -> String? {
        let name = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return name?.isEmpty == false ? name : nil
    }

    private static func duration(_ value: Any?) -> Double? {
        if let text = value as? String {
            return seconds(from: text)
        }
        // JSON booleans also bridge to numbers.
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let seconds = number.doubleValue
        return seconds.isFinite && seconds >= 0 ? seconds : nil
    }

    /// The action's text form, `Safari (1h 35m)`. Only the last parentheses hold the time, so a name can have
    /// its own.
    static func described(_ text: String) -> (name: String, seconds: Double)? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasSuffix(")"), let open = text.lastIndex(of: "(") else { return nil }
        let name = text[..<open].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let seconds = seconds(from: String(text[text.index(after: open)...].dropLast())) else {
            return nil
        }
        return (name, seconds)
    }

    /// Seconds from `95`, `1h 2m 3s`, `1 hr, 35 min`, `59s` or `1:02:03`.
    static func seconds(from text: String) -> Double? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let seconds = Double(text) {
            return seconds.isFinite && seconds >= 0 ? seconds : nil
        }
        if text.contains(":") {
            let parts = text.split(separator: ":", omittingEmptySubsequences: false).map { Int($0) }
            guard (2 ... 3).contains(parts.count), parts.allSatisfy({ ($0 ?? -1) >= 0 }) else { return nil }
            return Double(parts.compactMap(\.self).reduce(0) { $0 * 60 + $1 })
        }
        let term = /(\d+(?:\.\d+)?)\s*([A-Za-z]+)/
        var total = 0.0
        for match in text.matches(of: term) {
            guard let amount = Double(match.output.1), let unit = unitSeconds(match.output.2) else { return nil }
            total += amount * unit
        }
        // Everything but the terms must be separators, so "about an hour" or "5 apples" fails.
        let rest = text.replacing(term, with: "").filter { !" ,".contains($0) }
        return rest.isEmpty && text.contains(term) ? total : nil
    }

    private static func unitSeconds(_ unit: Substring) -> Double? {
        switch unit.lowercased() {
        case "h", "hr", "hrs", "hour", "hours": 3600
        case "m", "min", "mins", "minute", "minutes": 60
        case "s", "sec", "secs", "second", "seconds": 1
        default: nil
        }
    }
}
