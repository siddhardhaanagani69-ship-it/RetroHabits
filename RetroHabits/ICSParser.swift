import Foundation

/// Minimal iCalendar (.ics) parser — enough for Canvas calendar feeds.
enum ICSParser {

    static func parse(_ text: String) -> [AgendaItem] {
        // Unfold: lines beginning with a space/tab continue the previous line.
        var lines: [String] = []
        for rawLine in text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if (line.hasPrefix(" ") || line.hasPrefix("\t")), !lines.isEmpty {
                lines[lines.count - 1] += String(line.dropFirst())
            } else {
                lines.append(line)
            }
        }

        var items: [AgendaItem] = []
        var current: [String: (params: [String: String], value: String)]? = nil

        for line in lines {
            if line == "BEGIN:VEVENT" {
                current = [:]
                continue
            }
            if line == "END:VEVENT" {
                if let fields = current, let item = makeItem(from: fields) {
                    items.append(item)
                }
                current = nil
                continue
            }
            guard current != nil, let colon = line.firstIndex(of: ":") else { continue }

            let head = String(line[line.startIndex..<colon])
            let value = String(line[line.index(after: colon)...])
            let headParts = head.split(separator: ";").map(String.init)
            guard let name = headParts.first?.uppercased() else { continue }
            var params: [String: String] = [:]
            for part in headParts.dropFirst() {
                let kv = part.split(separator: "=", maxSplits: 1).map(String.init)
                if kv.count == 2 { params[kv[0].uppercased()] = kv[1] }
            }
            current?[name] = (params, value)
        }
        return items
    }

    private static func makeItem(from fields: [String: (params: [String: String], value: String)]) -> AgendaItem? {
        guard let summaryField = fields["SUMMARY"], let startField = fields["DTSTART"] else { return nil }
        guard let (start, isAllDay) = parseDate(startField.value, params: startField.params) else { return nil }

        var end: Date? = nil
        if let endField = fields["DTEND"], let (endDate, _) = parseDate(endField.value, params: endField.params) {
            end = endDate
        }
        let uid = fields["UID"]?.value ?? UUID().uuidString
        let location = fields["LOCATION"].map { unescape($0.value) }
        var notes = fields["DESCRIPTION"].map { unescape($0.value) }
        if let trimmed = notes, trimmed.count > 900 {
            notes = String(trimmed.prefix(900)) + "…"
        }
        let url = fields["URL"].flatMap { URL(string: $0.value.trimmingCharacters(in: .whitespaces)) }

        return AgendaItem(
            id: "canvas-\(uid)",
            title: unescape(summaryField.value),
            start: start,
            end: end,
            isAllDay: isAllDay,
            location: (location?.isEmpty == false) ? location : nil,
            notes: (notes?.isEmpty == false) ? notes : nil,
            url: url,
            source: .canvas
        )
    }

    /// Handles: 20260901T170000Z, 20260901T120000 (+ TZID param), and all-day 20260901.
    private static func parseDate(_ value: String, params: [String: String]) -> (Date, Bool)? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        if value.count == 8 || params["VALUE"] == "DATE" {
            formatter.dateFormat = "yyyyMMdd"
            formatter.timeZone = TimeZone.current
            if let date = formatter.date(from: String(value.prefix(8))) { return (date, true) }
            return nil
        }
        if value.hasSuffix("Z") {
            formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            formatter.timeZone = TimeZone(identifier: "UTC")
            if let date = formatter.date(from: value) { return (date, false) }
            return nil
        }
        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        if let tzid = params["TZID"], let timeZone = TimeZone(identifier: tzid) {
            formatter.timeZone = timeZone
        } else {
            formatter.timeZone = TimeZone.current
        }
        if let date = formatter.date(from: value) { return (date, false) }
        return nil
    }

    private static func unescape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\n", with: " ")
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\\\", with: "\\")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
