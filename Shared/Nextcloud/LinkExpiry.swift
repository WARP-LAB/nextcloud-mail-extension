import Foundation

/// When links expire (FR4): in a week, a month or a year, after a custom period of years, months, days and hours, or
/// never.
///
/// Nextcloud takes only a date and ends the link at the end of that day (docs/NEXTCLOUD.md, "Expiry"), so the period
/// is counted from the time of sending, and the link expires at the end of the day it reaches. Hours only matter
/// when they cross midnight.
enum LinkExpiry: Equatable {
    struct Period: Equatable, Codable {
        var years = 0
        var months = 0
        var days = 0
        var hours = 0
    }

    case never
    case after(Period)

    static let week = LinkExpiry.days(7)
    static let month = LinkExpiry.months(1)
    static let year = LinkExpiry.years(1)

    static func days(_ count: Int) -> LinkExpiry {
        .after(Period(days: count))
    }

    static func months(_ count: Int) -> LinkExpiry {
        .after(Period(months: count))
    }

    static func years(_ count: Int) -> LinkExpiry {
        .after(Period(years: count))
    }

    /// The `expireDate` to send with every share: the time of sending plus the period by calendar, as `YYYY-MM-DD`,
    /// or empty for never. When the server enforces a maximum, the date is shortened to it, and never becomes the
    /// maximum.
    func expireDate(from now: Date, calendar: Calendar = .current, limits: SharingLimits) -> String {
        var date: Date?
        if case .after(let period) = self {
            let components = DateComponents(
                year: period.years, month: period.months, day: period.days, hour: period.hours)
            date = calendar.date(byAdding: components, to: now)
        }
        if limits.expiryEnforced, let days = limits.defaultExpiryDays,
            let maximum = calendar.date(byAdding: .day, value: days, to: now)
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

extension LinkExpiry: Codable {
    private enum CodingKeys: String, CodingKey {
        case never, after
        // How earlier versions stored a period of one unit, such as {"days":{"_0":7}}.
        case days, months, years
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if values.contains(.never) {
            self = .never
        } else if let period = try values.decodeIfPresent(Period.self, forKey: .after) {
            self = .after(period)
        } else if let days = try values.decodeIfPresent(LegacyCount.self, forKey: .days) {
            self = .days(days.count)
        } else if let months = try values.decodeIfPresent(LegacyCount.self, forKey: .months) {
            self = .months(months.count)
        } else if let years = try values.decodeIfPresent(LegacyCount.self, forKey: .years) {
            self = .years(years.count)
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "No link expiry"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .never:
            try values.encode(true, forKey: .never)
        case .after(let period):
            try values.encode(period, forKey: .after)
        }
    }
}

/// How earlier versions stored a period's count, as `{"_0":7}`.
private struct LegacyCount: Codable {
    var count: Int

    private enum CodingKeys: String, CodingKey {
        case count = "_0"
    }
}
