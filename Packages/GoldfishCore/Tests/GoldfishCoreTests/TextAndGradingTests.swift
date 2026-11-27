import XCTest
@testable import GoldfishCore

final class TextToolsTests: XCTestCase {
    func testSentencesSplitOnEndPunctuationAndLineBreaks() {
        let text = "Cells are small. Mitochondria make ATP! Do they?\nYes, about 3.5 times more"
        XCTAssertEqual(TextTools.sentences(text), [
            "Cells are small.", "Mitochondria make ATP!", "Do they?", "Yes, about 3.5 times more",
        ])
    }

    func testWordsIgnorePunctuationAndCase() {
        XCTAssertEqual(TextTools.words("The cell's ATP-store, mostly."), ["the", "cell", "s", "atp", "store", "mostly"])
        XCTAssertTrue(TextTools.containsWords("Fancy goldfish with short, round bodies", "short round"))
        XCTAssertFalse(TextTools.containsWords("a goldfish", "gold"))
        XCTAssertFalse(TextTools.containsWords("anything", ""))
    }

    func testStableHashIsStableAndPadded() {
        XCTAssertEqual(StableHash.hex("goldfish"), StableHash.hex("goldfish"))
        XCTAssertNotEqual(StableHash.hex("goldfish"), StableHash.hex("goldfisH"))
        XCTAssertEqual(StableHash.hex("").count, 16)
        XCTAssertEqual(StableHash.hex(""), "cbf29ce484222325")
    }

    func testModelVersionCleaning() {
        XCTAssertEqual(ModelVersion.clean("Optional(\"gemini-3.5-flash-lite\")"), "gemini-3.5-flash-lite")
        XCTAssertEqual(ModelVersion.clean("apple-foundation-models-system-language-model"), ModelVersion.appleOnDevice)
        XCTAssertEqual(ModelVersion.clean("nil"), "")
        XCTAssertEqual(ModelVersion.tier(for: ModelVersion.appleOnDevice), .onDevice)
        XCTAssertEqual(ModelVersion.tier(for: "gemini-3.5-flash-lite"), .cloud)
    }

    func testErrorClassification() {
        XCTAssertEqual(ModelErrorKind.classify("HTTP 429 RESOURCE_EXHAUSTED"), .rateLimited)
        XCTAssertEqual(ModelErrorKind.classify("403 PERMISSION_DENIED: you must enforce Firebase App Check"), .appCheck)
        XCTAssertEqual(ModelErrorKind.classify("NSURLErrorDomain Code=-1009 The Internet connection appears to be offline."), .offline)
        XCTAssertEqual(ModelErrorKind.classify("guardrailViolation"), .refused)
        XCTAssertEqual(ModelErrorKind.classify("Model unavailable: appleIntelligenceNotEnabled"), .unavailable)
        XCTAssertEqual(ModelErrorKind.classify("boom"), .other)
    }
}

final class OwnWordsTests: XCTestCase {
    private let chapter = "The water then leaves through a bony flap called the operculum, which also protects the gills."

    func testCopiedRunOfEightWordsIsFlagged() {
        let checker = OwnWordsChecker(chapterText: chapter)
        XCTAssertTrue(checker.isCopied("Then it leaves through a bony flap called the operculum."))
        XCTAssertEqual(checker.copiedSentences(in: "Gills are neat. It leaves through a bony flap called the operculum.").count, 1)
    }

    func testParaphraseAndShortQuotesPass() {
        let checker = OwnWordsChecker(chapterText: chapter)
        XCTAssertFalse(checker.isCopied("Water exits under the operculum, a hard flap that guards the gills."))
        XCTAssertFalse(checker.isCopied("a bony flap called the operculum"))
    }

    func testFlaggedSentencesAreLeftOutOfTheFishText() {
        let checker = OwnWordsChecker(chapterText: chapter)
        let concept = Concept(id: "c1", name: "Gills", summary: "", whyQuestion: "")
        let lesson = Lesson(
            id: "l", chapterID: "ch", kind: .first,
            sections: ["c1": "My own idea here. It leaves through a bony flap called the operculum, which also protects the gills."],
            createdAt: Date()
        )
        XCTAssertEqual(LessonComposer.fishText(lesson: lesson, concepts: [concept], checker: checker), "My own idea here.")
    }

    func testPasteGuard() {
        let pasted = Array(repeating: "word", count: 13).joined(separator: " ")
        XCTAssertTrue(PasteGuard.isLargeInsert(old: "", new: pasted))
        XCTAssertFalse(PasteGuard.isLargeInsert(old: "The gills", new: "The gills take oxygen"))
        XCTAssertFalse(PasteGuard.isLargeInsert(old: pasted, new: ""))
    }

    func testLessonWordCountAndTokens() {
        let lesson = Lesson(id: "l", chapterID: "ch", kind: .first, sections: ["a": "one two", "b": "three"], createdAt: Date())
        XCTAssertEqual(LessonComposer.wordCount(lesson), 3)
        XCTAssertEqual(LessonComposer.estimatedTokens(words: 600), 840)
        XCTAssertTrue(LessonComposer.isEmpty(Lesson(id: "e", chapterID: "ch", kind: .first, sections: ["a": "  "], createdAt: Date())))
    }
}

final class FishGraderTests: XCTestCase {
    private let question = Question(
        id: "q", conceptID: "c", stem: "Which organelle makes ATP?",
        options: ["Ribosome", "Mitochondrion", "Golgi apparatus", "Lysosome"], correctIndex: 1,
        keyTerms: ["ribosome", "mitochondri", "golgi", "lysosome"], explanation: "",
        sourceQuote: "", modelSentence: "", pool: .practice
    )
    private let lesson = "Cells are small.\nMitochondria are the power plants of the cell.\nThe Golgi packs proteins into boxes."

    private func grade(_ reply: String, lesson: String? = nil) -> GradeResult {
        FishGrader.grade(FishReplyParser.parse(reply), question: question, lesson: lesson ?? self.lesson)
    }

    func testWordForWordMatchIsCorrect() {
        let result = grade("QUOTE: Mitochondria are the power plants of the cell.\nANSWER: B")
        XCTAssertEqual(result.verdict, .correct)
        XCTAssertEqual(result.traceSentence, "Mitochondria are the power plants of the cell.")
    }

    func testWrongOptionBackedByTheLessonIsAMixUp() {
        let result = grade("QUOTE: The Golgi packs proteins into boxes.\nANSWER: C")
        XCTAssertEqual(result.verdict, .mixUp)
        XCTAssertEqual(result.traceSentence, "The Golgi packs proteins into boxes.")
    }

    func testParaphraseIsAGap() {
        XCTAssertEqual(grade("QUOTE: Mitochondria are power stations.\nANSWER: B").verdict, .gap)
    }

    func testTooShortAndTooLongAreGaps() {
        XCTAssertEqual(grade("QUOTE: Mitochondria are\nANSWER: B").verdict, .gap)
        let long = Array(repeating: "mitochondria", count: 31).joined(separator: " ")
        XCTAssertEqual(grade("QUOTE: \(long)\nANSWER: B", lesson: long).verdict, .gap)
    }

    func testQuoteWithoutTheChosenKeyTermIsAGap() {
        let result = grade("QUOTE: Cells are small.\nANSWER: B")
        XCTAssertEqual(result.verdict, .gap)
        XCTAssertNotNil(result.note)
    }

    func testNotTaughtUnreadableAndEmptyLesson() {
        XCTAssertEqual(grade("QUOTE: NONE\nANSWER: NONE").verdict, .gap)
        XCTAssertEqual(FishGrader.grade(nil, question: question, lesson: lesson).verdict, .gap)
        XCTAssertEqual(grade("QUOTE: Mitochondria are the power plants of the cell.\nANSWER: B", lesson: "").verdict, .gap)
    }

    func testCacheKeyDependsOnLessonAndQuestion() {
        let a = AnswerCacheKey.key(lesson: lesson, question: question)
        XCTAssertEqual(a, AnswerCacheKey.key(lesson: lesson, question: question))
        XCTAssertNotEqual(a, AnswerCacheKey.key(lesson: lesson + " More.", question: question))
        var other = question
        other.stem = "Which organelle makes most ATP?"
        XCTAssertNotEqual(a, AnswerCacheKey.key(lesson: lesson, question: other))
    }

    func testShortAnswerParsing() {
        XCTAssertEqual(ShortAnswerPrompt.parse("MATCH"), .match)
        XCTAssertEqual(ShortAnswerPrompt.parse("I would say partial."), .partial)
        XCTAssertEqual(ShortAnswerPrompt.parse("**MISS**"), .miss)
        XCTAssertNil(ShortAnswerPrompt.parse("mismatch"))
    }
}

/// Replies with a fixed list, one per call.
final class QueueFishEngine: FishEngine {
    private var replies: [String]
    private(set) var calls = 0

    init(_ replies: [String]) {
        self.replies = replies
    }

    func reply(to prompt: String) async throws -> FishReply {
        calls += 1
        let text = replies.isEmpty ? "" : replies.removeFirst()
        return FishReply(text: text, tier: .onDevice, modelVersion: ModelVersion.appleOnDevice)
    }
}

final class FishAskerTests: XCTestCase {
    private let exam = SampleChapter.exam(compiledAt: Date(timeIntervalSince1970: 0))

    func testUnreadableReplyIsRetriedOnceThenGraded() async throws {
        let question = exam.questions[0]
        let letter = FishPrompt.letter(for: question.correctIndex)
        let engine = QueueFishEngine(["I don't know", "QUOTE: \(question.modelSentence)\nANSWER: \(letter)"])
        let answer = try await FishAsker(engine: engine).ask(question, lesson: question.modelSentence)
        XCTAssertEqual(engine.calls, 2)
        XCTAssertEqual(answer.verdict, .correct)
        XCTAssertEqual(answer.tier, .onDevice)
    }

    func testTwoUnreadableRepliesAreAGap() async throws {
        let engine = QueueFishEngine(["hmm", "still hmm"])
        let answer = try await FishAsker(engine: engine).ask(exam.questions[0], lesson: "Some lesson text here.")
        XCTAssertEqual(engine.calls, 2)
        XCTAssertEqual(answer.verdict, .gap)
        XCTAssertEqual(answer.choice, .notTaught)
    }
}
