import Foundation

/// A calendar day. The review rules work in whole days, so every schedule uses this type.
public struct Day: Codable, Hashable, Comparable, CustomStringConvertible {
    public let index: Int

    public init(index: Int) {
        self.index = index
    }

    public init(_ date: Date, calendar: Calendar = .current) {
        let reference = calendar.startOfDay(for: Day.referenceDate)
        let start = calendar.startOfDay(for: date)
        index = calendar.dateComponents([.day], from: reference, to: start).day ?? 0
    }

    public func adding(_ days: Int) -> Day {
        Day(index: index + days)
    }

    /// Positive when `other` is later.
    public func days(until other: Day) -> Int {
        other.index - index
    }

    /// Midnight at the start of this day.
    public func date(calendar: Calendar = .current) -> Date {
        let reference = calendar.startOfDay(for: Day.referenceDate)
        return calendar.date(byAdding: .day, value: index, to: reference) ?? reference
    }

    public static func < (lhs: Day, rhs: Day) -> Bool {
        lhs.index < rhs.index
    }

    public var description: String {
        "day \(index)"
    }

    private static let referenceDate = Date(timeIntervalSinceReferenceDate: 0)
}

/// The app's sense of "now". Diagnostics can move it forward to test spaced reviews.
public protocol AppClock {
    var now: Date { get }
}

public struct SystemClock: AppClock {
    public init() {}

    public var now: Date {
        Date()
    }
}

/// The Diagnostics "time machine": real time shifted by whole days.
public struct OffsetClock: AppClock {
    public var offsetDays: Int
    public var calendar: Calendar

    public init(offsetDays: Int, calendar: Calendar = .current) {
        self.offsetDays = offsetDays
        self.calendar = calendar
    }

    public var now: Date {
        calendar.date(byAdding: .day, value: offsetDays, to: Date()) ?? Date()
    }
}

/// A clock for tests.
public struct FixedClock: AppClock {
    public var now: Date

    public init(_ now: Date) {
        self.now = now
    }
}
