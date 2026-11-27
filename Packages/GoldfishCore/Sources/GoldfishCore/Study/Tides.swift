import Foundation

/// When chapters and concepts are next due.
public enum Tides {
    /// Fresh Water sessions, in days after the chapter was first taught.
    public static let freshWaterOffsets = [1, 3, 7, 14]
    /// Your Turn box gaps, in days.
    public static let boxGaps = [1, 3, 7, 14]
    /// With an exam date, the next gap is about this share of the days left.
    /// A heuristic informed by Cepeda et al. (2008), not a formula from the research.
    public static let examShare = 0.15
    public static let maxGap = 14

    /// The next Fresh Water day, or nil when nothing more is due before the exam.
    public static func nextFreshWater(_ progress: ChapterProgress, examDay: Day?) -> Day? {
        guard let first = progress.firstTaughtOn else { return nil }
        let last = progress.lastSessionOn ?? first

        if let exam = examDay, exam > last {
            let daysLeft = last.days(until: exam)
            if daysLeft <= 1 {
                return nil
            }
            let gap = min(maxGap, max(1, Int((examShare * Double(daysLeft)).rounded())))
            return min(last.adding(gap), exam.adding(-1))
        }

        let done = progress.freshWaterDone
        guard done < freshWaterOffsets.count else {
            return last.adding(freshWaterOffsets.last ?? maxGap)
        }
        return max(first.adding(freshWaterOffsets[done]), last.adding(1))
    }

    /// Records a finished teaching session (a Pop Quiz on the lesson) and reschedules.
    public static func recordSession(
        _ progress: ChapterProgress,
        kind: LessonKind,
        on day: Day,
        examDay: Day?
    ) -> ChapterProgress {
        var updated = progress
        if updated.firstTaughtOn == nil {
            updated.firstTaughtOn = day
        }
        if kind == .freshWater && updated.lastFreshWaterOn != day {
            updated.freshWaterDone += 1
            updated.lastFreshWaterOn = day
        }
        if let last = updated.lastSessionOn {
            if last < day {
                updated.lastSessionOn = day
            }
        } else {
            updated.lastSessionOn = day
        }
        updated.nextDueOn = nextFreshWater(updated, examDay: examDay)
        return updated
    }

    public static func isDue(_ progress: ChapterProgress?, today: Day) -> Bool {
        guard let due = progress?.nextDueOn else { return false }
        return due <= today
    }

    public static func isDue(_ progress: ConceptProgress?, today: Day) -> Bool {
        guard let due = progress?.dueOn else { return false }
        return due <= today
    }

    /// Moves a concept between Your Turn boxes after an unaided answer.
    /// The box moves up at most once per day. A miss returns it to the first box.
    /// "Sure but wrong" questions are kept to be asked first next time.
    public static func scheduleConcept(
        _ progress: ConceptProgress,
        correct: Bool,
        sure: Bool?,
        questionID: String,
        today: Day,
        examDay: Day?
    ) -> ConceptProgress {
        var updated = progress
        if correct {
            if updated.lastBoxChangeOn != today {
                updated.box = min(updated.box + 1, boxGaps.count - 1)
                updated.lastBoxChangeOn = today
            }
            updated.retryQuestionIDs.removeAll { $0 == questionID }
        } else {
            updated.box = 0
            updated.lastBoxChangeOn = today
            if sure == true && !updated.retryQuestionIDs.contains(questionID) {
                updated.retryQuestionIDs.append(questionID)
            }
        }

        var due = today.adding(correct ? boxGaps[updated.box] : 1)
        if let exam = examDay, due >= exam {
            due = max(exam.adding(-1), today.adding(1))
        }
        updated.dueOn = due
        return updated
    }
}

/// Days taught in the last week. There is no reset to zero.
public enum Streak {
    /// Oldest first, ending today.
    public static func week(_ days: [Day], endingOn today: Day, length: Int = 7) -> [Bool] {
        let taught = Set(days)
        return (0..<length).reversed().map { taught.contains(today.adding(-$0)) }
    }

    public static func count(_ days: [Day], endingOn today: Day, length: Int = 7) -> Int {
        week(days, endingOn: today, length: length).filter { $0 }.count
    }
}
