import Foundation

/// When links expire (FR4): in a week, a month or a year, after a custom number of days, months or years, or never.
enum LinkExpiry: Equatable, Codable {
    case never
    case days(Int)
    case months(Int)
    case years(Int)

    static let week = LinkExpiry.days(7)
    static let month = LinkExpiry.months(1)
    static let year = LinkExpiry.years(1)

    /// The `expireDate` to send with every share: today plus the period by calendar, as `YYYY-MM-DD`, or empty for
    /// never. When the server enforces a maximum, the date is shortened to it, and never becomes the maximum.
    func expireDate(today: Date, calendar: Calendar = .current, limits: SharingLimits) -> String {
        var date: Date?
        switch self {
        case .never:
            date = nil
        case .days(let count):
            date = calendar.date(byAdding: .day, value: count, to: today)
        case .months(let count):
            date = calendar.date(byAdding: .month, value: count, to: today)
        case .years(let count):
            date = calendar.date(byAdding: .year, value: count, to: today)
        }
        if limits.expiryEnforced, let days = limits.defaultExpiryDays,
            let maximum = calendar.date(byAdding: .day, value: days, to: today)
        {
            date = min(date ?? maximum, maximum)
        }
        guard let date else {
            return ""
        }
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
