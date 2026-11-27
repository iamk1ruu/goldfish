import Foundation

/// Concept states. Mastery is decided by the student's own
/// unaided answers, never by the fish's score.
public enum MasteryRules {
    /// Successive relearning, with three correct retrievals as the criterion.
    public static let daysNeeded = 3

    public static func state(_ progress: ConceptProgress?) -> ConceptState {
        guard let progress = progress else { return .notTaught }
        if Set(progress.correctDays).count >= daysNeeded {
            return .mastered
        }
        if progress.slipped {
            return .recalled
        }
        switch progress.fishLevel {
        case .notTaught: return .notTaught
        case .taught: return .taught
        case .recalled: return .recalled
        }
    }

    /// After a Pop Quiz: the concept is Taught (or Recalled, for a Fresh Water lesson)
    /// when every question asked about it was answered correctly. Misses never lower the level.
    public static func afterQuiz(
        _ progress: ConceptProgress,
        answers: [FishAnswer],
        writtenFromMemory: Bool
    ) -> ConceptProgress {
        guard !answers.isEmpty, answers.allSatisfy({ $0.verdict == .correct }) else {
            return progress
        }
        var updated = progress
        let level: FishLevel = writtenFromMemory ? .recalled : .taught
        if level > updated.fishLevel {
            updated.fishLevel = level
        }
        return updated
    }

    /// After a Your Turn answer. Three correct days make a concept Mastered.
    /// A miss starts the count again, and a mastered concept slips back to Recalled.
    public static func afterYourTurn(_ progress: ConceptProgress, correct: Bool, day: Day) -> ConceptProgress {
        var updated = progress
        if correct {
            if !updated.correctDays.contains(day) {
                updated.correctDays.append(day)
            }
            if Set(updated.correctDays).count >= daysNeeded {
                updated.slipped = false
            }
        } else {
            let wasMastered = Set(updated.correctDays).count >= daysNeeded
            updated.correctDays = []
            if wasMastered {
                updated.slipped = true
            }
        }
        return updated
    }

    /// "You've mastered 4 of 8 concepts."
    public static func masteredCount(_ concepts: [Concept], progress: [String: ConceptProgress]) -> Int {
        concepts.filter { state(progress[$0.id]) == .mastered }.count
    }
}
