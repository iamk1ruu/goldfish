import Foundation

/// Limits on the sentence the fish quotes as evidence.
public struct QuoteRules: Equatable {
    public var minWords: Int
    public var maxWords: Int

    public init(minWords: Int = 3, maxWords: Int = 30) {
        self.minWords = minWords
        self.maxWords = maxWords
    }
}

/// Code-only checks that decide whether a fish answer earns credit.
/// No model is involved, so the result cannot be talked around.
public enum QuoteCheck {
    /// True when the quote is a real, reasonably short span of the lesson.
    /// The length cap stops a model from passing by quoting the whole lesson.
    public static func isVerbatim(_ quote: String, in lesson: String, rules: QuoteRules = QuoteRules()) -> Bool {
        let cleaned = TextNormalizer.cleanQuote(quote)
        guard !cleaned.isEmpty else { return false }
        let words = TextNormalizer.wordCount(cleaned)
        guard words >= rules.minWords, words <= rules.maxWords else { return false }
        return TextNormalizer.normalize(lesson).contains(cleaned)
    }

    /// True when the quote mentions the key term of the option the fish chose.
    /// This catches a model that answers from memory and cites an unrelated sentence.
    public static func containsKeyTerm(_ quote: String, keyTerm: String) -> Bool {
        let term = TextNormalizer.normalize(keyTerm)
        guard !term.isEmpty else { return false }
        return TextNormalizer.normalize(quote).contains(term)
    }
}
