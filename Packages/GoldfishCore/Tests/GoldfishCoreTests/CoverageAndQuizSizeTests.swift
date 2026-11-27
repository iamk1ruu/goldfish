import XCTest
@testable import GoldfishCore

/// A whole document is covered, and quiz sizes follow the content instead of fixed numbers.
final class DocumentPlanTests: XCTestCase {
    /// The sample's six sections, each repeated with a new heading, eight times over: about 4,700 words.
    private var longDocument: String {
        let sections = SampleChapter.text.components(separatedBy: "\n\n").dropFirst()
        var text = "Fish Biology\n\n"
        for round in 1...8 {
            for section in sections {
                var lines = section.components(separatedBy: "\n")
                lines[0] += " \(round)"
                text += lines.joined(separator: "\n") + "\n\n"
            }
        }
        return text
    }

    func testConceptCountFollowsLength() {
        XCTAssertEqual(ExamPlan.conceptTarget(words: 200), 3)
        XCTAssertEqual(ExamPlan.conceptTarget(words: 900), 6)
        XCTAssertEqual(ExamPlan.conceptTarget(words: 5_000), 10)
    }

    func testAShortChapterIsOnePart() {
        let parts = ExamPlan.parts(title: SampleChapter.title, text: SampleChapter.text)
        XCTAssertEqual(parts.count, 1)
        XCTAssertEqual(parts.first?.title, SampleChapter.title)
    }

    func testALongDocumentSplitsAtHeadingsAndKeepsEveryWord() {
        let parts = ExamPlan.parts(title: "Fish Biology", text: longDocument)
        XCTAssertGreaterThanOrEqual(parts.count, 4)
        XCTAssertTrue(parts.allSatisfy { $0.words <= ExamPlan.partWords + 200 })
        XCTAssertEqual(TextTools.words(parts.map { $0.text }.joined(separator: "\n")), TextTools.words(longDocument))
        XCTAssertTrue(parts[1].title.hasPrefix("Fish Biology 2: "))
        XCTAssertEqual(parts.last?.count, parts.count)
    }

    func testADocumentOnOneLineStillSplits() {
        let flat = String(repeating: SampleChapter.text.replacingOccurrences(of: "\n", with: " ") + " ", count: 6)
        XCTAssertGreaterThanOrEqual(ExamPlan.parts(title: "Flat", text: flat).count, 2)
    }
}

final class CoverageTests: XCTestCase {
    private let date = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func testNoQuestionsCoverNothing() {
        let result = CoverageCheck.check(questions: [], chapterText: SampleChapter.text)
        XCTAssertGreaterThan(result.coverage.passages, 0)
        XCTAssertEqual(result.coverage.covered, 0)
        XCTAssertEqual(result.uncovered.count, result.coverage.passages)
    }

    func testAQuotedPassageIsCovered() {
        let exam = SampleChapter.exam(compiledAt: date)
        let result = CoverageCheck.check(questions: exam.questions, chapterText: SampleChapter.text)
        XCTAssertGreaterThan(result.coverage.covered, 0)
        XCTAssertEqual(result.coverage.covered + result.uncovered.count, result.coverage.passages)
        // The operculum question quotes the first section, so that passage is covered.
        XCTAssertFalse(result.uncovered.contains { $0.contains("operculum") })
    }
}

final class QuizSizeTests: XCTestCase {
    private let date = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private var exam: Exam { SampleChapter.exam(compiledAt: date) }

    func testFishRoundAsksOneQuestionPerConcept() {
        let round = QuizPicker.fishRound(exam: exam, stats: [:])
        XCTAssertEqual(round.count, exam.concepts.count)
        XCTAssertEqual(Set(round.map { $0.conceptID }).count, exam.concepts.count)
    }

    func testFishRoundAsksAMissedQuestionAgain() {
        let exam = self.exam
        let practice = exam.questions(in: .practice, concept: exam.concepts[0].id)
        guard let missed = practice.last else { return XCTFail("the first concept has no practice questions") }
        let stats = [missed.id: QuestionStat(timesAsked: 1, timesMissed: 1, lastVerdict: .mixUp)]
        XCTAssertEqual(QuizPicker.fishRound(exam: exam, stats: stats).first?.id, missed.id)
    }

    func testEverythingDealsOneCardPerConcept() {
        let exam = self.exam
        let cards = QuizPicker.cards(exam: exam, chapterID: "sample", progress: [:], history: [], today: Day(index: 10), everything: true)
        XCTAssertEqual(cards.count, Set(exam.questions(in: .yourTurn).map { $0.conceptID }).count)
        XCTAssertTrue(cards.allSatisfy { $0.chapterID == "sample" })
    }

    func testOnlyDueConceptsGetCards() {
        let exam = self.exam
        guard let dueConcept = exam.concepts.first(where: { !exam.questions(in: .yourTurn, concept: $0.id).isEmpty }) else {
            return XCTFail("the sample has no Your Turn questions")
        }
        var progress: [String: ConceptProgress] = [:]
        for concept in exam.concepts {
            var entry = ConceptProgress(conceptID: concept.id)
            entry.dueOn = Day(index: concept.id == dueConcept.id ? 5 : 20)
            progress[concept.id] = entry
        }
        let cards = QuizPicker.cards(exam: exam, chapterID: "sample", progress: progress, history: [], today: Day(index: 10), everything: false)
        XCTAssertEqual(cards.map { $0.question.conceptID }, [dueConcept.id])
    }

    func testDeckCardsTakeTurnsBetweenChapters() {
        let exam = self.exam
        let cards = QuizPicker.deckCards(exams: [("a", exam), ("b", exam)], progress: [:], history: [], today: Day(index: 10))
        XCTAssertEqual(cards.prefix(2).map { $0.chapterID }, ["a", "b"])
    }
}
