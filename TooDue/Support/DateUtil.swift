import Foundation

/// Date helpers for the server's wire formats: dates are "YYYY-MM-DD" strings,
/// times are "HH:MM", interpreted in the user's local calendar (same as the PWA).
enum DateUtil {
    static var calendar: Calendar { Calendar.current }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func parseDay(_ s: String) -> Date? {
        dayFormatter.date(from: s).map { calendar.startOfDay(for: $0) }
    }

    static func dayString(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    static func today() -> Date {
        calendar.startOfDay(for: Date())
    }

    static func isOverdue(_ day: String, reference: Date = Date()) -> Bool {
        guard let d = parseDay(day) else { return false }
        return d < calendar.startOfDay(for: reference)
    }

    static func isToday(_ day: String, reference: Date = Date()) -> Bool {
        guard let d = parseDay(day) else { return false }
        return calendar.isDate(d, inSameDayAs: reference)
    }

    /// Relative label matching the PWA: Today / Tomorrow / weekday (within a week)
    /// / "Mon 3 Feb" / adds year when not this year.
    static func relativeLabel(for day: String, reference: Date = Date()) -> String {
        guard let d = parseDay(day) else { return day }
        let start = calendar.startOfDay(for: reference)
        let days = calendar.dateComponents([.day], from: start, to: d).day ?? 0
        switch days {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case 2...6:
            let f = DateFormatter()
            f.dateFormat = "EEEE"
            return f.string(from: d)
        default:
            let f = DateFormatter()
            let sameYear = calendar.component(.year, from: d) == calendar.component(.year, from: start)
            f.dateFormat = sameYear ? "E d MMM" : "E d MMM yyyy"
            return f.string(from: d)
        }
    }

    /// "HH:MM" → localized short time ("2:30 PM").
    static func timeLabel(_ time: String) -> String {
        let parts = time.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
              let date = calendar.date(bySettingHour: h, minute: m, second: 0, of: Date())
        else { return time }
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: date)
    }

    static func timeString(_ date: Date) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}
