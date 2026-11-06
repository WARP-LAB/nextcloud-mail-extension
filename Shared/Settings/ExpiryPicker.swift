import SwiftUI

/// FR4: in a week, a month or a year, after a custom period of years, months, days and hours, or never.
struct ExpiryPicker: View {
    enum Choice: Hashable {
        case week, month, year, custom, never
    }

    @Binding var expiry: LinkExpiry
    var label = "Links expire"
    /// Whether the custom choice is shown, which a custom period equal to a preset, such as 7 days, needs.
    @State private var custom = false

    var body: some View {
        Picker(label, selection: choice) {
            Text("In a week").tag(Choice.week)
            Text("In a month").tag(Choice.month)
            Text("In a year").tag(Choice.year)
            Text("After a custom period").tag(Choice.custom)
            Text("Never").tag(Choice.never)
        }
        .onAppear {
            custom = Self.preset(expiry) == nil
        }
        if choice.wrappedValue == .custom {
            // Two rows of two, so that each number keeps its unit next to it, also in the narrow popover.
            LabeledContent("After") {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    GridRow {
                        amount("year", "years", \.years)
                        amount("month", "months", \.months)
                    }
                    GridRow {
                        amount("day", "days", \.days)
                        amount("hour", "hours", \.hours)
                    }
                }
            }
            Text(
                "Counted from sending. Nextcloud ends a link at the end of a day, so the link expires at the end of "
                    + "the day the period reaches, and hours only matter when they cross midnight."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    private func amount(_ unit: String, _ units: String, _ part: WritableKeyPath<LinkExpiry.Period, Int>)
        -> some View
    {
        HStack(spacing: 4) {
            TextField(units, value: binding(part), format: .number)
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(width: 44)
            Stepper(units, value: binding(part), in: 0...9999)
                .labelsHidden()
            Text(period[keyPath: part] == 1 ? unit : units)
                .fixedSize()
                .frame(minWidth: 48, alignment: .leading)
        }
    }

    private var choice: Binding<Choice> {
        Binding {
            custom ? .custom : Self.preset(expiry) ?? .custom
        } set: { choice in
            custom = choice == .custom
            switch choice {
            case .week:
                expiry = .week
            case .month:
                expiry = .month
            case .year:
                expiry = .year
            case .never:
                expiry = .never
            case .custom:
                if expiry == .never {
                    expiry = .days(14)
                }
            }
        }
    }

    /// The custom period, or two weeks to start from when links don't expire.
    private var period: LinkExpiry.Period {
        if case .after(let period) = expiry {
            return period
        }
        return LinkExpiry.Period(days: 14)
    }

    private func binding(_ part: WritableKeyPath<LinkExpiry.Period, Int>) -> Binding<Int> {
        Binding {
            period[keyPath: part]
        } set: { value in
            var changed = period
            changed[keyPath: part] = min(max(value, 0), 9999)
            expiry = .after(changed)
        }
    }

    private static func preset(_ expiry: LinkExpiry) -> Choice? {
        if expiry == .week {
            return .week
        }
        if expiry == .month {
            return .month
        }
        if expiry == .year {
            return .year
        }
        return expiry == .never ? .never : nil
    }
}
