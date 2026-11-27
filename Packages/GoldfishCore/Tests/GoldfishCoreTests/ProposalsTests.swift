import XCTest
@testable import GoldfishCore


final class StemmerTests: XCTestCase {
    func testWordFormsMeetAtOneStem() {
        let families = [
            ["diffuse", "diffuses", "diffused", "diffusing", "diffusion"],
            ["swell", "swells", "swelling"],
            ["membrane", "membranes"],
            ["concentrate", "concentrated", "concentration", "concentrations"],
            ["dilute", "diluted", "dilution"],
            ["study", "studies", "studying"],
            ["move", "moves", "moving", "movement"],
            ["breathe", "breathes", "breathing"],
            ["transport", "transported", "transporting"],
            ["protect", "protects", "protection"],
            ["run", "running"],
        ]
        for family in families {
            let stems = Set(family.map(Stemmer.stem))
            XCTAssertEqual(stems.count, 1, "\(family) gave \(stems)")
        }
    }

    func testDifferentWordsStayApart() {
        XCTAssertNotEqual(Stemmer.stem("organ"), Stemmer.stem("organism"))
        XCTAssertNotEqual(Stemmer.stem("live"), Stemmer.stem("liver"))
        XCTAssertNotEqual(Stemmer.stem("cell"), Stemmer.stem("cellulose"))
    }

    func testShortWordsAndNumbersAreLeftAlone() {
        XCTAssertEqual(Stemmer.stem("gas"), "gas")
        XCTAssertEqual(Stemmer.stem("use"), "use")
        XCTAssertEqual(Stemmer.stem("co2"), "co2")
        XCTAssertEqual(Stemmer.stem("process"), Stemmer.stem("processes"))
    }
}

/// Stands in for Apple's sentence embedding: every word of a group points along that group's axis,
/// so sentences about the same group mean the same thing even with no word in common.
private struct GroupEmbedder: SentenceEmbedder {
    let groups: [Set<String>]

    func vector(for text: String) -> [Double]? {
        let words = TextTools.words(text)
        let vector = groups.map { group in Double(words.filter { group.contains($0) }.count) }
        return vector.contains { $0 > 0 } ? vector : nil
    }
}

private struct NoEmbedder: SentenceEmbedder {
    func vector(for text: String) -> [Double]? { nil }
}

final class OrlaSearchTests: XCTestCase {
    private let date = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private var index: PassageIndex { PassageIndex(chapters: [SampleChapter.chapter(createdAt: date)]) }

    /// The retrieval check: questions a student might ask in their own words, and a phrase from
    /// the passage that answers each. Checked against a Node port of this search before it was written.
    func testRetrievalCheckOnTheSampleChapter() {
        let checks: [(question: String, phrase: String)] = [
            ("Why doesn't a goldfish swell up?", "swelling up"),
            ("How does a fish breathe underwater?", "oxygen out of water"),
            ("What lets a fish stay at one depth without swimming?", "hover at one depth"),
            ("How do fish sense movement in muddy water?", "lateral line"),
            ("Why does blood flow the opposite way to the water?", "countercurrent"),
            ("What happens to a goldfish in cold water?", "cold water"),
            ("How does a goldfish refill its swim bladder?", "top up its bladder"),
            ("what protects the gills", "operculum"),
        ]
        for check in checks {
            let top = index.search(check.question).first?.text.lowercased() ?? ""
            XCTAssertTrue(top.contains(check.phrase), "\"\(check.question)\" found: \(top.prefix(60))")
        }
    }

    func testAStemFindsTheChaptersWordForm() {
        // The chapter says "swelling"; the student says "swell".
        let hit = index.find("Why doesn't it swell?").hits.first
        XCTAssertTrue(hit?.passage.text.contains("swelling up") ?? false)
        XCTAssertEqual(hit?.matchedWords, true)
    }

    func testFollowUpsAreToldFromNewQuestions() {
        XCTAssertTrue(TutorFollowUp.isFollowUp("Why doesn't it swell up?"))
        XCTAssertTrue(TutorFollowUp.isFollowUp("Why?"))
        XCTAssertTrue(TutorFollowUp.isFollowUp("What about plants?"))
        XCTAssertTrue(TutorFollowUp.isFollowUp("How does it get rid of the water?"))
        XCTAssertFalse(TutorFollowUp.isFollowUp("What is osmosis?"))
        XCTAssertFalse(TutorFollowUp.isFollowUp("Why does water keep getting into a goldfish?"))
        XCTAssertFalse(TutorFollowUp.isFollowUp("Why is the sky blue?"))
    }

    func testAFollowUpIsSearchedWithTheQuestionBefore() {
        let search = index.find("Why?", previous: "Why does water seep into a goldfish?")
        XCTAssertTrue(search.followUp)
        XCTAssertTrue(search.passages.first?.text.contains("osmosis") ?? false)

        let alone = index.find("Why?")
        XCTAssertFalse(alone.followUp)
        XCTAssertTrue(alone.hits.isEmpty)
    }

    func testANewQuestionIgnoresThePreviousOne() {
        let search = index.find("What protects the gills?", previous: "Why does water keep getting into a goldfish?")
        XCTAssertFalse(search.followUp)
        XCTAssertTrue(search.passages.first?.text.contains("operculum") ?? false)
    }

    func testMeaningFindsAPassageWithNoWordInCommon() {
        let chapter = Chapter(
            id: "plants", title: "Plants",
            sourceText: "Making food\nLeaves capture sunlight and turn it into sugar. The sugar feeds the whole plant.\n\nHolding on\nRoots anchor the soil and absorb minerals from it.",
            createdAt: date
        )
        let embedder = GroupEmbedder(groups: [
            ["leaves", "sunlight", "sugar", "plant", "food", "light", "greens", "power"],
            ["roots", "soil", "minerals", "anchor"],
        ])
        let plain = PassageIndex(chapters: [chapter])
        XCTAssertEqual(plain.passages.count, 2)
        let question = "How do greens get power from light?"
        XCTAssertTrue(plain.find(question).hits.isEmpty, "no word is shared, so words alone find nothing")
        XCTAssertFalse(plain.find(question, embedder: embedder).searchedMeaning, "an index that was never embedded searches words only")

        let embedded = plain.embedded(with: embedder)
        XCTAssertTrue(embedded.searchesMeaning)
        let search = embedded.find(question, embedder: embedder)
        XCTAssertTrue(search.searchedMeaning)
        XCTAssertEqual(search.hits.count, 1)
        XCTAssertTrue(search.hits.first?.passage.text.contains("sunlight") ?? false)
        XCTAssertEqual(search.hits.first?.matchedMeaning, true)
        XCTAssertEqual(search.hits.first?.matchedWords, false)
        XCTAssertEqual(search.bestSimilarity ?? 0, 1, accuracy: 0.0001)

        // A higher floor than the match reaches finds nothing.
        XCTAssertTrue(embedded.find("roots and light", embedder: embedder, meaningFloor: 0.99).hits.allSatisfy { $0.matchedWords })
    }

    func testAPhoneWithNoEmbeddingSearchesWordsOnly() {
        let embedded = index.embedded(with: NoEmbedder())
        XCTAssertFalse(embedded.searchesMeaning)
        XCTAssertEqual(embedded.find("what protects the gills", embedder: NoEmbedder()).passages, index.search("what protects the gills"))
    }

    func testPromptCarriesTheEarlierQuestionForAFollowUp() {
        let passages = index.search("swelling dilute urine")
        let prompt = TutorPrompt.build(
            question: "Why doesn't it swell up?", previous: "Why does water keep getting into a goldfish?",
            deckName: "Science", fishName: "Finn", passages: passages
        )
        XCTAssertTrue(prompt.contains("for context: Why does water keep getting into a goldfish?"))
        XCTAssertTrue(prompt.hasSuffix("Student's question: Why doesn't it swell up?"))
        let single = TutorPrompt.build(question: "What protects the gills?", deckName: "Science", fishName: "Finn", passages: passages)
        XCTAssertFalse(single.contains("for context"))
    }

    func testScriptedTutorNamesTheWordInAnyForm() {
        let passages = index.search("Why doesn't it swell?")
        let reply = ScriptedTutor.reply(question: "Why doesn't it swell?", passages: passages, fishName: "Finn")
        XCTAssertTrue(reply.hint.contains("\"swell\""), reply.hint)
    }

    func testMeaningFloorIsARemoteSetting() {
        var settings = GoldfishSettings()
        XCTAssertEqual(settings.tutorMeaningFloor, PassageIndex.defaultMeaningFloor)
        settings.apply("0.62", forKey: "tutor_meaning_floor")
        XCTAssertEqual(settings.tutorMeaningFloor, 0.62, accuracy: 0.0001)
        settings.apply("3", forKey: "tutor_meaning_floor")
        XCTAssertEqual(settings.tutorMeaningFloor, 0.62, accuracy: 0.0001, "out of range is ignored")
        XCTAssertEqual(settings.value(forKey: "tutor_meaning_floor"), "0.62")
    }
}

final class WhereToLookTests: XCTestCase {
    func testEveryQuestionPointsToThePassageThatHoldsItsQuote() {
        let date = Date(timeIntervalSinceReferenceDate: 0)
        let index = PassageIndex(chapters: [SampleChapter.chapter(createdAt: date)])
        for question in SampleChapter.exam(compiledAt: date).questions {
            let passage = index.passage(holding: question.sourceQuote)
            XCTAssertTrue(
                passage.map { TextTools.containsWords($0.text, question.sourceQuote) } ?? false,
                "no passage holds: \(question.sourceQuote)"
            )
        }
        XCTAssertNil(index.passage(holding: "  "))
    }

    func testTheReadingPauseFollowsTheLengthWithinLimits() {
        XCTAssertEqual(ReadingPause.seconds(for: "Short."), ReadingPause.shortest)
        XCTAssertEqual(ReadingPause.seconds(for: Array(repeating: "word", count: 60).joined(separator: " ")), 15, accuracy: 0.001)
        XCTAssertEqual(ReadingPause.seconds(for: Array(repeating: "word", count: 400).joined(separator: " ")), ReadingPause.longest)
    }
}

final class OneMoreGoTests: XCTestCase {
    func testMissedCardsComeBackOnceInOrder() {
        let exam = SampleChapter.exam(compiledAt: Date(timeIntervalSinceReferenceDate: 0))
        let cards = exam.questions(in: .yourTurn).prefix(4).map { QuizCard(chapterID: SampleChapter.id, question: $0) }
        XCTAssertEqual(cards.count, 4)
        func answer(_ card: QuizCard, correct: Bool) -> StudentAnswer {
            StudentAnswer(
                questionID: card.question.id, conceptID: card.question.conceptID, recallText: "", chosenIndex: 0,
                sure: nil, correct: correct, answeredAt: Date(timeIntervalSinceReferenceDate: 0), day: Day(index: 1)
            )
        }
        let firstTries = [answer(cards[0], correct: true), answer(cards[1], correct: false), answer(cards[2], correct: true), answer(cards[3], correct: false)]
        XCTAssertEqual(OneMoreGo.cards(from: Array(cards), firstTries: firstTries).map(\.id), [cards[1].id, cards[3].id])
        XCTAssertTrue(OneMoreGo.cards(from: Array(cards), firstTries: firstTries.filter(\.correct)).isEmpty)
    }
}

/// Grades each Grading Check case with whatever `grade` returns for it.
private struct GradingStub: FishEngine {
    let grade: (GradingCheck.Case) -> String

    func reply(to prompt: String) async throws -> FishReply {
        let item = GradingCheck.cases.first { prompt.hasSuffix("STUDENT: \($0.answer)") }
        return FishReply(text: item.map(grade) ?? "?", tier: .scripted, modelVersion: "stub")
    }
}

private struct FailingEngine: FishEngine {
    struct Down: Error {}
    func reply(to prompt: String) async throws -> FishReply { throw Down() }
}

/// The one-word reply a grader gives for a grade.
private func word(_ grade: ShortAnswerGrade) -> String {
    grade.rawValue.uppercased()
}

final class GradingCheckTests: XCTestCase {
    func testTheCasesAreBalanced() {
        let cases = GradingCheck.cases
        XCTAssertEqual(cases.count, 12)
        XCTAssertEqual(Set(cases.map(\.id)).count, 12)
        for grade in [ShortAnswerGrade.match, .partial, .miss] {
            XCTAssertEqual(cases.filter { $0.expected == grade }.count, 4)
        }
    }

    func testAPerfectGraderPasses() async {
        let result = await GradingCheck.run(engine: GradingStub { word($0.expected) })
        XCTAssertEqual(result.agreed, 12)
        XCTAssertEqual(result.harmful, 0)
        XCTAssertTrue(result.passed)
        XCTAssertEqual(result.modelVersion, "stub")
    }

    func testTwoHarmlessSlipsStillPass() async {
        // A match called partly right, and a partly right answer called a match. Neither is harmful.
        let slips = ["osmosis-match": "PARTIAL", "urine-partial": "MATCH"]
        let result = await GradingCheck.run(engine: GradingStub { slips[$0.id] ?? word($0.expected) })
        XCTAssertEqual(result.agreed, 10)
        XCTAssertEqual(result.harmful, 0)
        XCTAssertTrue(result.passed)
    }

    func testThreeSlipsFail() async {
        let slips: Set<String> = ["osmosis-partial", "active-partial", "urine-partial"]
        let result = await GradingCheck.run(engine: GradingStub { slips.contains($0.id) ? "MATCH" : word($0.expected) })
        XCTAssertEqual(result.agreed, 9)
        XCTAssertFalse(result.passed)
    }

    func testCallingAWrongAnswerRightFailsEvenWithElevenAgreed() async {
        let result = await GradingCheck.run(engine: GradingStub { $0.id == "urine-miss" ? "MATCH" : word($0.expected) })
        XCTAssertEqual(result.agreed, 11)
        XCTAssertEqual(result.harmful, 1)
        XCTAssertFalse(result.passed)
        XCTAssertTrue(GradingCheck.report(result, source: "stub", device: "test", date: Date()).contains("HARMFUL"))
    }

    func testFailedCallsCannotPass() async {
        let result = await GradingCheck.run(engine: FailingEngine())
        XCTAssertEqual(result.trials.count, 12)
        XCTAssertEqual(result.agreed, 0)
        XCTAssertFalse(result.passed)
    }

    func testAStoppedRunCannotPass() async {
        let result = await GradingCheck.run(engine: GradingStub { word($0.expected) }, shouldStop: { true })
        XCTAssertTrue(result.trials.isEmpty)
        XCTAssertFalse(result.passed)
    }

    func testTheResultIsSavedWithTheData() throws {
        var data = GoldfishData()
        data.gradingCheck = GradingCheckRecord(passed: true, agreed: 11, total: 12, harmful: 0, modelVersion: "apple", ranAt: Date(timeIntervalSinceReferenceDate: 1000))
        let loaded = try JSONDecoder().decode(GoldfishData.self, from: JSONEncoder().encode(data))
        XCTAssertEqual(loaded.gradingCheck, data.gradingCheck)
        XCTAssertNil(try JSONDecoder().decode(GoldfishData.self, from: Data("{}".utf8)).gradingCheck)
    }
}
