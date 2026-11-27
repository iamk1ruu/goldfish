import XCTest
@testable import GoldfishCore

final class ExamValidatorTests: XCTestCase {
    private let chapter = WordText("Mitochondria make most of the cell's ATP. The Golgi packages proteins for delivery.")

    private func draft(
        options: [String] = ["Mitochondrion", "Ribosome", "Golgi apparatus", "Lysosome"],
        keys: [String] = ["mitochondri", "ribosome", "golgi", "lysosome"],
        correct: Int = 0,
        quote: String = "Mitochondria make most of the cell's ATP",
        sentence: String = "Mitochondria are the cell's power plants.",
        pool: String = "practice"
    ) -> QuestionDraft {
        QuestionDraft(
            pool: pool, stem: "Which organelle makes most ATP?", options: options, correctIndex: correct,
            keyTerms: keys, explanation: "Mitochondria run cellular respiration.",
            sourceQuote: quote, modelSentence: sentence
        )
    }

    func testValidQuestionPasses() {
        XCTAssertEqual(ExamValidator.problems(draft(), chapter: chapter), [])
    }

    func testEachRuleIsEnforced() {
        XCTAssertFalse(ExamValidator.problems(draft(options: ["A1", "B1", "C1"], keys: ["a1x", "b1x", "c1x"]), chapter: chapter).isEmpty)
        XCTAssertFalse(ExamValidator.problems(draft(options: ["Same", "Same", "Golgi", "Lysosome"]), chapter: chapter).isEmpty)
        XCTAssertFalse(ExamValidator.problems(draft(correct: 4), chapter: chapter).isEmpty)
        XCTAssertFalse(ExamValidator.problems(draft(keys: ["mitochondri", "ribosome", "golgi"]), chapter: chapter).isEmpty)
        XCTAssertFalse(ExamValidator.problems(draft(keys: ["mitochondri", "mitochondri", "golgi", "lysosome"]), chapter: chapter).isEmpty)
        XCTAssertFalse(ExamValidator.problems(draft(keys: ["nucleus", "ribosome", "golgi", "lysosome"]), chapter: chapter).isEmpty)
        XCTAssertFalse(ExamValidator.problems(draft(keys: ["mi", "ribosome", "golgi", "lysosome"]), chapter: chapter).isEmpty)
        XCTAssertFalse(ExamValidator.problems(draft(quote: "Mitochondria are tiny batteries"), chapter: chapter).isEmpty)
        XCTAssertFalse(ExamValidator.problems(draft(sentence: "They are the power plants."), chapter: chapter).isEmpty)
        XCTAssertFalse(ExamValidator.problems(draft(sentence: "Mitochondria, not the Golgi, make ATP."), chapter: chapter).isEmpty)
        XCTAssertFalse(ExamValidator.problems(draft(pool: "bonus"), chapter: chapter).isEmpty)
    }

    func testKeyTermFoundInAnotherOptionIsRejected() {
        let problems = ExamValidator.problems(
            draft(options: ["Golgi body", "Ribosome", "Golgi apparatus", "Lysosome"], keys: ["body", "ribosome", "golgi", "lysosome"],
                  sentence: "The Golgi body makes ATP."),
            chapter: chapter
        )
        XCTAssertTrue(problems.contains { $0.contains("also appears") })
    }

    func testBuildDropsBadQuestionsAndAsksForRetryWhenTooFewSurvive() {
        let exam = ExamDraft(concepts: [
            ConceptDraft(name: "Energy", summary: "", whyQuestion: "", questions: [draft(), draft(quote: "not in the chapter at all")]),
            ConceptDraft(name: "Empty", summary: "", whyQuestion: "", questions: [draft(pool: "bonus")]),
        ])
        let result = ExamValidator.build(
            draft: exam, chapterID: "ch", chapterText: "Mitochondria make most of the cell's ATP.",
            compiledBy: "test", compiledAt: Date()
        )
        XCTAssertEqual(result.kept, 1)
        XCTAssertEqual(result.dropped.count, 2)
        XCTAssertEqual(result.exam.concepts.map { $0.name }, ["Energy"])
        XCTAssertEqual(result.exam.questions.first?.id, "ch.c1.p1")
        XCTAssertTrue(result.needsRetry)
    }

    func testBalancingKeepsEachAnswerWithItsKeyTerm() {
        let questions = (0..<8).map { index in
            Question(
                id: "q\(index)", conceptID: "c", stem: "S\(index)", options: ["Right", "W1", "W2", "W3"], correctIndex: 0,
                keyTerms: ["right", "w1x", "w2x", "w3x"], explanation: "", sourceQuote: "", modelSentence: "", pool: .practice
            )
        }
        let balanced = ExamValidator.balanceLetters(questions, seed: 42)
        for letter in 0..<4 {
            XCTAssertEqual(balanced.filter { $0.correctIndex == letter }.count, 2)
        }
        for question in balanced {
            XCTAssertEqual(question.correctOption, "Right")
            XCTAssertEqual(question.keyTerms[question.correctIndex], "right")
        }
        XCTAssertEqual(balanced, ExamValidator.balanceLetters(questions, seed: 42))
    }

    func testDraftDecodingIsLenientAndStripsFences() throws {
        let text = """
        ```json
        {"concepts":[{"name":"Energy","questions":[{"pool":"practice","stem":"Q?","options":["a","b","c","d"]},{"stem":"no pool"}]}]}
        ```
        """
        let draft = try CloudJSON.decode(ExamDraft.self, from: text)
        XCTAssertEqual(draft.concepts.count, 1)
        XCTAssertEqual(draft.concepts[0].questions.count, 2)
        XCTAssertEqual(draft.concepts[0].questions[0].correctIndex, -1)
        XCTAssertEqual(draft.concepts[0].whyQuestion, "")
    }

    func testPoolNames() {
        XCTAssertEqual(QuestionPool(cloudValue: "yourTurn"), .yourTurn)
        XCTAssertEqual(QuestionPool(cloudValue: "your_turn"), .yourTurn)
        XCTAssertEqual(QuestionPool(cloudValue: "Final"), .finalExam)
        XCTAssertNil(QuestionPool(cloudValue: "bonus"))
    }

    func testExamPromptCarriesTheChapter() {
        let prompt = CloudPrompts.exam(title: "Cells", chapterText: "Mitochondria make ATP. \"\"\" stray fence")
        XCTAssertTrue(prompt.contains("TITLE: Cells"))
        XCTAssertTrue(prompt.contains("Mitochondria make ATP."))
        XCTAssertEqual(prompt.components(separatedBy: "\"\"\"").count, 3)
    }
}

final class SampleChapterTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    func testHandWrittenExamPassesValidationWithNoDrops() {
        let result = ExamValidator.build(
            draft: SampleChapter.draft, chapterID: SampleChapter.id, chapterText: SampleChapter.text,
            compiledBy: "hand-written", compiledAt: date
        )
        for dropped in result.dropped {
            XCTFail("\(dropped.concept): \(dropped.stem) -> \(dropped.reasons)")
        }
        XCTAssertEqual(result.exam.concepts.count, 6)
        XCTAssertEqual(result.exam.questions.count, 30)
        XCTAssertEqual(result.exam.questions(in: .practice).count, 18)
        XCTAssertEqual(result.exam.questions(in: .finalExam).count, 6)
        XCTAssertEqual(result.exam.questions(in: .yourTurn).count, 6)
        XCTAssertFalse(result.needsRetry)
    }

    func testCorrectAnswersAreSpreadAcrossLetters() {
        let exam = SampleChapter.exam(compiledAt: date)
        for letter in 0..<4 {
            let count = exam.questions.filter { $0.correctIndex == letter }.count
            XCTAssertTrue((7...8).contains(count), "letter \(letter): \(count)")
        }
    }

    func testFixtureLessonIsInTheStudentsOwnWordsAndFitsTheBowl() {
        let exam = SampleChapter.exam(compiledAt: date)
        let checker = OwnWordsChecker(chapterText: SampleChapter.text)
        let sections = SampleChapter.fixtureSections(exam: exam)
        for text in sections.values {
            XCTAssertEqual(checker.copiedSentences(in: text), [])
        }
        let lesson = Lesson(id: "l", chapterID: SampleChapter.id, kind: .first, sections: sections, createdAt: date)
        XCTAssertLessThan(LessonComposer.wordCount(lesson), 600)
    }

    func testScriptedFishGivesCorrectMixUpAndGapOnTheFixture() async throws {
        let exam = SampleChapter.exam(compiledAt: date)
        let lesson = Lesson(
            id: "l", chapterID: SampleChapter.id, kind: .first,
            sections: SampleChapter.fixtureSections(exam: exam), createdAt: date
        )
        let text = LessonComposer.fishText(lesson: lesson, concepts: exam.concepts, checker: nil)
        let asker = FishAsker(engine: ScriptedFishEngine(questions: exam.questions))

        func verdict(_ id: String) async throws -> FishVerdict {
            let question = try XCTUnwrap(exam.question(id))
            return try await asker.ask(question, lesson: text).verdict
        }
        let gills = try await verdict("sample.c1.p1")
        let bladder = try await verdict("sample.c3.p2")
        let lateral = try await verdict("sample.c4.p2")
        XCTAssertEqual(gills, .correct)
        XCTAssertEqual(bladder, .mixUp)
        XCTAssertEqual(lateral, .gap)
    }

    func testScriptedFishPassesTheFairExamCheck() async {
        let exam = SampleChapter.exam(compiledAt: date)
        let asker = FishAsker(engine: ScriptedFishEngine(questions: exam.questions))
        let results = await FairExamCheck.run(questions: exam.questions, asker: asker)
        XCTAssertEqual(results.count, 30)
        let failed = results.filter { !$0.value }.map { $0.key }.sorted()
        XCTAssertEqual(failed, [], "questions the scripted fish failed from their own teaching sentence")
    }

    func testFairExamCheckDropsFailuresButKeepsEachPoolCovered() {
        let exam = SampleChapter.exam(compiledAt: date)
        let results = ["sample.c1.p1": false, "sample.c1.f1": false, "sample.c1.p2": true]
        let (checked, dropped) = FairExamCheck.apply(results, to: exam)
        XCTAssertEqual(dropped, ["sample.c1.p1"])
        XCTAssertNotNil(checked.question("sample.c1.f1"), "the concept's only final question stays")
        XCTAssertEqual(checked.question("sample.c1.f1")?.fairCheck, false)
        XCTAssertEqual(checked.question("sample.c1.p2")?.fairCheck, true)
    }
}
