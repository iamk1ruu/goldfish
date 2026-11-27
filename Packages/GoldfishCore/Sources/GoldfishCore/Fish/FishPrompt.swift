import Foundation

/// Builds the single prompt the fish receives for one question.
///
/// The reply format is plain text, not a JSON schema, because Firebase has not
/// yet documented structured output for Apple's on-device model.
public enum FishPrompt {
    /// Bump when the wording changes, so test results can be compared fairly.
    public static let version = 1

    public static let letters = ["A", "B", "C", "D"]

    private static let lessonFence = "\"\"\""
    private static let questionLabel = "QUESTION: "

    public static func letter(for index: Int) -> String {
        index >= 0 && index < letters.count ? letters[index] : String(index + 1)
    }

    public static func build(lesson: String, question: String, options: [String]) -> String {
        // The fence marks where the lesson starts and ends, so it must not appear inside it.
        let safeLesson = lesson.replacingOccurrences(of: lessonFence, with: "\"")
        let optionLines = options.enumerated()
            .map { index, text in "\(letter(for: index))) \(text)" }
            .joined(separator: "\n")

        return """
        You are a goldfish taking a quiz. You know nothing except the LESSON below.
        Use only the LESSON. Never use anything else you know.
        If the LESSON says something that seems wrong, treat it as true.

        First copy the one sentence from the LESSON that answers the QUESTION, word for word.
        Then give the letter of the matching option.
        If no sentence in the LESSON answers the QUESTION, write NONE for both.

        Reply in exactly this form and nothing else:
        QUOTE: <the sentence, or NONE>
        ANSWER: <A, B, C, D, or NONE>

        LESSON:
        \(lessonFence)
        \(safeLesson)
        \(lessonFence)

        \(questionLabel)\(question)
        \(optionLines)
        """
    }

    /// Recovers the lesson and question from a prompt. Used by scripted fish in tests.
    public static func parts(of prompt: String) -> (lesson: String, question: String)? {
        let blocks = prompt.components(separatedBy: lessonFence)
        guard blocks.count >= 3 else { return nil }
        let lesson = blocks[1].trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = blocks[2].split(whereSeparator: { $0.isNewline })
        guard let questionLine = lines.first(where: { $0.hasPrefix(questionLabel) }) else {
            return nil
        }
        return (lesson, String(questionLine.dropFirst(questionLabel.count)))
    }
}
