import Foundation

/// A stand-in fish for the Simulator and tests. It looks for the lesson sentence that
/// shares the most words with the question and contains an option's key term.
/// It behaves like a literal-minded pupil, so it produces Correct, Mix-up and Gap
/// outcomes, but its results say nothing about a real model.
public struct ScriptedFishEngine: FishEngine {
    public let questions: [Question]
    public let delayMs: Int

    /// A sentence must share at least this many content words with the question.
    public static let minimumOverlap = 2

    static let stopWords: Set<String> = [
        "the", "and", "for", "are", "but", "not", "you", "all", "any", "can", "has", "had",
        "was", "its", "his", "her", "how", "what", "which", "when", "where", "why", "who",
        "does", "did", "that", "this", "with", "from", "into", "than", "then", "they", "them",
        "their", "there", "these", "those", "your", "about", "goldfish", "fish", "water",
    ]

    public init(questions: [Question], delayMs: Int = 0) {
        self.questions = questions
        self.delayMs = delayMs
    }

    public func reply(to prompt: String) async throws -> FishReply {
        if delayMs > 0 {
            try await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
        }
        return FishReply(text: replyText(to: prompt), tier: .scripted, modelVersion: "scripted-fish")
    }

    public func replyText(to prompt: String) -> String {
        guard let parts = FishPrompt.parts(of: prompt),
              let question = questions.first(where: { $0.stem == parts.question })
        else {
            return "QUOTE: NONE\nANSWER: NONE"
        }
        return ScriptedFishEngine.answer(question: question, lesson: parts.lesson)
    }

    public static func answer(question: Question, lesson: String) -> String {
        let stemWords = contentWords(question.stem)
        var best: (overlap: Int, option: Int, sentence: String)? = nil
        for sentence in TextTools.sentences(lesson) {
            let normalized = TextNormalizer.normalize(sentence)
            let overlap = contentWords(sentence).intersection(stemWords).count
            guard overlap >= minimumOverlap else { continue }
            for (option, key) in question.keyTerms.enumerated() {
                let term = TextNormalizer.normalize(key)
                guard !term.isEmpty, normalized.contains(term) else { continue }
                if best == nil || overlap > best!.overlap {
                    best = (overlap, option, sentence)
                }
            }
        }
        guard let pick = best else {
            return "QUOTE: NONE\nANSWER: NONE"
        }
        return "QUOTE: \(pick.sentence)\nANSWER: \(FishPrompt.letter(for: pick.option))"
    }

    static func contentWords(_ text: String) -> Set<String> {
        Set(TextTools.words(text).filter { $0.count >= 3 && !stopWords.contains($0) })
    }
}

/// Writes exams without the cloud: only the built-in sample chapter is known.
public struct FixtureExamCompiler: ExamCompiler {
    public struct UnknownChapter: Error, CustomStringConvertible {
        public var description: String {
            "This build has no cloud connection, so it can only use the sample chapter."
        }
    }

    public init() {}

    public func compile(title: String, chapterText: String, pdfData: Data?) async throws -> ExamDraft {
        guard TextTools.wordSequence(chapterText) == TextTools.wordSequence(SampleChapter.text) else {
            throw UnknownChapter()
        }
        return SampleChapter.draft
    }
}

/// Writes Report Card lists without the cloud, from the results alone.
public struct FixtureReportWriter: ReportWriter {
    public init() {}

    public func write(_ input: ReportInput) async throws -> ReportDraft {
        let right = Set(input.fishResults.filter { $0.result == "correct" }.map { $0.concept })
        let wrong = Set(input.fishResults.filter { $0.result != "correct" }.map { $0.concept })
            .union(input.studentResults.filter { !$0.correct }.map { $0.concept })
        let mixUps = input.fishResults.filter { $0.result.hasPrefix("mix-up") && !$0.sentence.isEmpty }
        return ReportDraft(
            explainedWell: right.subtracting(wrong).sorted().map { "\($0): explained clearly." },
            misconceptions: mixUps.map { "\"\($0.sentence)\" led to a wrong answer." },
            reviewNext: wrong.sorted().map { "Review \($0)." }
        )
    }
}
