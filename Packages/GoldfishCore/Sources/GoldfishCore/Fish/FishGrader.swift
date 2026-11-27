import Foundation

public struct GradeResult: Equatable {
    public let verdict: FishVerdict
    /// The lesson sentence that backed the answer.
    public let traceSentence: String?
    /// Why an answer that picked an option still counted as a Gap.
    public let note: String?
}

/// Decides in code, not by a model, whether a fish answer counts.
///
/// An answer counts only when the quote is a real 3 to 30 word span of the lesson
/// and contains the key term of the option the fish chose. Anything else is a Gap.
public enum FishGrader {
    public static func grade(
        _ parsed: ParsedFishReply?,
        question: Question,
        lesson: String,
        rules: QuoteRules = QuoteRules()
    ) -> GradeResult {
        guard let parsed = parsed else {
            return GradeResult(verdict: .gap, traceSentence: nil, note: "The reply could not be read.")
        }
        guard case .option(let index) = parsed.choice, question.keyTerms.indices.contains(index) else {
            return GradeResult(verdict: .gap, traceSentence: nil, note: nil)
        }
        guard QuoteCheck.isVerbatim(parsed.quote, in: lesson, rules: rules) else {
            return GradeResult(
                verdict: .gap, traceSentence: nil,
                note: "The fish picked an answer but could not point to a sentence in your lesson."
            )
        }
        guard QuoteCheck.containsKeyTerm(parsed.quote, keyTerm: question.keyTerms[index]) else {
            return GradeResult(
                verdict: .gap, traceSentence: nil,
                note: "The sentence the fish quoted does not mention its answer."
            )
        }
        let trace = traceSentence(for: parsed.quote, in: lesson) ?? parsed.quote
        let verdict: FishVerdict = index == question.correctIndex ? .correct : .mixUp
        return GradeResult(verdict: verdict, traceSentence: trace, note: nil)
    }

    /// The lesson sentence that contains the quote.
    public static func traceSentence(for quote: String, in text: String) -> String? {
        guard !TextTools.wordSequence(quote).isEmpty else { return nil }
        for sentence in TextTools.sentences(text) where TextTools.containsWords(sentence, quote) {
            return sentence
        }
        // A quote that spans two sentences: return the first sentence it touches.
        let quoteWords = TextTools.words(quote)
        guard let first = quoteWords.first else { return nil }
        let opening = quoteWords.prefix(3).joined(separator: " ")
        for sentence in TextTools.sentences(text) where TextTools.containsWords(sentence, opening.isEmpty ? first : opening) {
            return sentence
        }
        return nil
    }
}

/// Builds the cache key for one fish answer. The same lesson and question never cost a second call.
public enum AnswerCacheKey {
    public static func key(lesson: String, question: Question) -> String {
        let parts = [
            "v\(FishPrompt.version)",
            lesson,
            question.id,
            question.stem,
            question.options.joined(separator: "|"),
        ]
        return StableHash.hex(parts.joined(separator: "\u{1F}"))
    }

    public static func lessonHash(_ lesson: String) -> String {
        StableHash.hex(lesson)
    }
}

/// Asks the fish one question and grades the reply.
public struct FishAsker {
    public let engine: FishEngine
    public let rules: QuoteRules

    public init(engine: FishEngine, rules: QuoteRules = QuoteRules()) {
        self.engine = engine
        self.rules = rules
    }

    /// An unreadable reply is retried once, then counted as a Gap. Engine errors are thrown.
    public func ask(_ question: Question, lesson: String) async throws -> FishAnswer {
        let prompt = FishPrompt.build(lesson: lesson, question: question.stem, options: question.options)
        let started = Date()
        var reply = try await engine.reply(to: prompt)
        var parsed = FishReplyParser.parse(reply.text, optionCount: question.options.count)
        if parsed == nil {
            reply = try await engine.reply(to: prompt)
            parsed = FishReplyParser.parse(reply.text, optionCount: question.options.count)
        }
        let latencyMs = Int(Date().timeIntervalSince(started) * 1000)
        let grade = FishGrader.grade(parsed, question: question, lesson: lesson, rules: rules)
        return FishAnswer(
            questionID: question.id,
            choice: parsed?.choice ?? .notTaught,
            quote: parsed?.quote ?? "",
            verdict: grade.verdict,
            traceSentence: grade.traceSentence,
            tier: reply.tier,
            modelVersion: reply.modelVersion,
            latencyMs: latencyMs,
            raw: reply.text,
            note: grade.note
        )
    }
}
