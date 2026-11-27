import Foundation

/// The forgiving streak, shown as an 8-bit fire.
///
/// It counts days you taught Finn, not calendar days, so a missed day never adds to it.
/// One missed day is forgiven: the fire dims to embers and the count stays. Two missed days in a row
/// put the fire out, and the next day you teach lights a new one. The best run is always kept.
/// A missed day never wipes progress.
public struct FireStreak: Equatable {
    public enum Flame: String, Equatable {
        /// You taught today.
        case lit
        /// You taught yesterday. Teach today to grow the fire.
        case waiting
        /// You missed yesterday. Teach today and the fire keeps its count.
        case embers
        /// Two or more days missed, or never taught. The next teaching day starts a new fire.
        case out
    }

    public let flame: Flame
    /// Teaching days in the current fire. Zero only when the fire is out.
    public let days: Int
    /// The longest fire so far, in teaching days.
    public let best: Int

    /// The most missed days in a row that a fire survives.
    public static let forgivenDays = 1

    public init(flame: Flame, days: Int, best: Int) {
        self.flame = flame
        self.days = days
        self.best = best
    }

    public static func compute(_ teachingDays: [Day], today: Day) -> FireStreak {
        // Days after today can exist when Diagnostics moves the clock back. They do not count.
        let days = Array(Set(teachingDays.filter { $0 <= today })).sorted()
        guard let last = days.last else {
            return FireStreak(flame: .out, days: 0, best: 0)
        }
        var best = 0
        var run = 0
        var previous: Day?
        for day in days {
            if let previous = previous, previous.days(until: day) <= forgivenDays + 1 {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previous = day
        }
        let gap = last.days(until: today)
        let flame: Flame
        switch gap {
        case 0: flame = .lit
        case 1: flame = .waiting
        case 2: flame = .embers
        default: flame = .out
        }
        return FireStreak(flame: flame, days: flame == .out ? 0 : run, best: best)
    }
}
