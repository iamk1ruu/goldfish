import Foundation

/// Prompts for the two cloud-only jobs: writing the Hidden Exam and the Report Card.
public enum CloudPrompts {
    /// Bump when the exam prompt changes. Stored on each exam.
    /// 2: the number of concepts follows the chapter's length, and every paragraph must be covered.
    public static let examVersion = 2

    /// The Hidden Exam for one chapter. The number of concepts follows the chapter's length
    /// (`ExamPlan.conceptTarget`), and every paragraph must be covered by some question.
    /// A top-up pass for passages the first pass missed uses the same prompt on just those passages.
    public static func exam(title: String, chapterText: String) -> String {
        let safeText = chapterText.replacingOccurrences(of: "\"\"\"", with: "\"")
        let concepts = ExamPlan.conceptTarget(words: TextTools.words(chapterText).count)
        return """
        You are writing a hidden exam for a study app. A student will explain this chapter in their own words to a pupil, and the pupil will then answer your questions using only the student's explanation. Later the student answers some of your questions too.

        Read the CHAPTER and choose \(concepts) key concepts that together cover everything in it: every paragraph must belong to at least one concept, and no part of the chapter may be left out. For each concept write:
        - name: 2 to 5 words
        - summary: one sentence
        - whyQuestion: one "why" or "how" question a curious pupil would ask about this concept
        - questions: 3 with pool "practice", 1 with pool "final", and 2 with pool "yourTurn"

        Spread the questions' sourceQuotes across the whole chapter, so that every paragraph is quoted by at least one question.

        Every question is multiple choice:
        - stem: a clear question that can be answered from the chapter alone
        - options: exactly 4 short options of 1 to 8 words. All plausible, exactly one correct. Never "all of the above" or "none of the above".
        - correctIndex: the position of the correct option, 0 to 3
        - keyTerms: one per option, in the same order as the options. A key term is a word or short phrase of at least 3 letters, copied from its option, that any sentence teaching that option would have to contain. A key term must not appear in any other option. A word stem is fine, for example "mitochondri" for "Mitochondrion".
        - explanation: one or two sentences on why the answer is right
        - sourceQuote: 5 to 30 words copied exactly from the CHAPTER that support the answer
        - modelSentence: one plain sentence a student could write to teach the answer. It must contain the correct option's key term and none of the other key terms.

        Questions in different pools must test different facts or angles, so practising one pool does not give away another. Use the chapter's language. Return JSON only.

        TITLE: \(title)

        CHAPTER:
        \"\"\"
        \(safeText)
        \"\"\"
        """
    }

    public static func report(_ input: ReportInput) -> String {
        let fishLines = input.fishResults.map { line in
            "- [\(line.concept)] \(line.question) | Result: \(line.result) | Sentence used: \(line.sentence.isEmpty ? "none" : line.sentence)"
        }
        let studentLines = input.studentResults.map { line in
            "- [\(line.concept)] \(line.question) | Chose: \(line.chosen) | Correct answer: \(line.correctAnswer) | \(line.correct ? "right" : "wrong") | Sure: \(line.sure)"
        }
        return """
        You are writing a short report card for a student. The student taught a chapter to a pupil, a cartoon goldfish named \(input.fishName), and then answered questions without help.

        Use only the information below. Speak to the student as "you". Be specific and kind, and point to the student's own lesson sentences where you can. Do not re-teach the chapter.

        Return JSON with three lists, each with at most 4 items of one short sentence:
        - explainedWell: concepts the lesson explained clearly
        - misconceptions: wrong or misleading ideas found in the lesson or in the student's answers, each with what is actually true
        - reviewNext: what to review before the next session

        CHAPTER: \(input.chapterTitle)
        CONCEPTS: \(input.concepts.joined(separator: "; "))

        LESSON:
        \"\"\"
        \(input.lesson)
        \"\"\"

        PUPIL'S FINAL EXAM (answered only from the lesson):
        \(fishLines.isEmpty ? "- none" : fishLines.joined(separator: "\n"))

        STUDENT'S OWN ANSWERS:
        \(studentLines.isEmpty ? "- none" : studentLines.joined(separator: "\n"))
        """
    }
}
