import Foundation

/// In a Your Turn, every card missed on the first try comes back once at the end of the same
/// sitting. Successive relearning asks for each item to be recalled correctly once per session,
/// and a second try right after the answer was shown is the cheapest way to get there.
///
/// The second try is practice. It is never recorded as a `StudentAnswer`, so it changes no score,
/// no box, no due date and no mastery count. "You got 11 of 14" still counts first tries only.
/// The final exam has no second try.
public enum OneMoreGo {
    /// The cards to deal again, in the order they were first dealt, each once.
    public static func cards(from cards: [QuizCard], firstTries: [StudentAnswer]) -> [QuizCard] {
        let missed = Set(firstTries.filter { !$0.correct }.map(\.questionID))
        var seen = Set<String>()
        return cards.filter { card in
            missed.contains(card.question.id) && seen.insert(card.question.id).inserted
        }
    }
}
