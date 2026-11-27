import Foundation

/// Turns the Bowl's sections into the single lesson text the fish reads.
public enum LessonComposer {
    /// Words times 1.4. Token counting is not available in hybrid mode.
    public static func estimatedTokens(words: Int) -> Int {
        Int((Double(words) * 1.4).rounded(.up))
    }

    /// A section's text without sentences copied from the chapter.
    public static func countedText(_ section: String, checker: OwnWordsChecker?) -> String {
        let sentences = TextTools.sentences(section)
        let kept = checker.map { checker in sentences.filter { !checker.isCopied($0) } } ?? sentences
        return kept.joined(separator: " ")
    }

    /// Sections in concept order, one per line. Concept names are left out on purpose:
    /// a heading such as "Mitochondria and ATP" would let the fish quote it without
    /// the student having taught anything.
    public static func fishText(lesson: Lesson, concepts: [Concept], checker: OwnWordsChecker?) -> String {
        concepts
            .map { countedText(lesson.section($0.id), checker: checker) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    public static func wordCount(_ lesson: Lesson) -> Int {
        lesson.sections.values.reduce(0) { $0 + TextNormalizer.wordCount($1) }
    }

    public static func isEmpty(_ lesson: Lesson) -> Bool {
        lesson.sections.values.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

/// Optional grading of the student's typed answer. Only shown, never scored.
public enum ShortAnswerPrompt {
    public static func build(question: Question, answer: String) -> String {
        """
        Grade a student's short answer against the answer key.
        Judge the meaning, not the wording or the spelling.
        Reply with exactly one word: MATCH if it means the same as the key, PARTIAL if it is partly right or vague, MISS if it is wrong or blank.

        QUESTION: \(question.stem)
        KEY: \(question.correctOption). \(question.explanation)
        STUDENT: \(answer.trimmingCharacters(in: .whitespacesAndNewlines))
        """
    }

    public static func parse(_ reply: String) -> ShortAnswerGrade? {
        let tokens = reply.uppercased()
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { !$0.isEmpty }
        for token in tokens {
            switch token {
            case "MATCH": return .match
            case "PARTIAL": return .partial
            case "MISS": return .miss
            default: continue
            }
        }
        return nil
    }
}
