import XCTest
@testable import GoldfishCore

final class DeckTests: XCTestCase {
    private let date = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private var exam: Exam { SampleChapter.exam(compiledAt: date) }

    func testSampleChapterGoesIntoAScienceDeck() {
        var data = GoldfishData()
        data.addChapter(SampleChapter.chapter(createdAt: date), exam: exam)
        XCTAssertEqual(data.decks.map { $0.name }, ["Science"])
        XCTAssertEqual(data.chapters.first?.deckID, data.decks.first?.id)
        XCTAssertEqual(data.currentDeck?.name, "Science")
    }

    func testNewChapterJoinsTheCurrentDeck() {
        var data = GoldfishData()
        let science = data.addDeck(name: "Science", color: .green)
        let code = data.addDeck(name: "Programming", color: .indigo)
        XCTAssertEqual(data.currentDeckID, code.id)
        data.addChapter(Chapter(id: "loops", title: "Loops", sourceText: "A loop repeats code.", createdAt: date), exam: exam)
        XCTAssertEqual(data.chapters(inDeck: code.id).map { $0.id }, ["loops"])
        XCTAssertTrue(data.chapters(inDeck: science.id).isEmpty)
    }

    func testChaptersFromBeforeDecksGetADeckWhenLoaded() throws {
        var old = GoldfishData()
        old.chapters = [Chapter(id: "c1", title: "Old chapter", sourceText: "Text.", createdAt: date)]
        let loaded = try JSONDecoder().decode(GoldfishData.self, from: JSONEncoder().encode(old))
        XCTAssertEqual(loaded.decks.map { $0.name }, ["My deck"])
        XCTAssertEqual(loaded.chapters.first?.deckID, loaded.decks.first?.id)
        XCTAssertEqual(loaded.currentDeckID, loaded.decks.first?.id)
    }

    func testDeletingADeckDeletesItsChaptersButNeverTheLastDeck() {
        var data = GoldfishData()
        let science = data.addDeck(name: "Science")
        data.addChapter(SampleChapter.chapter(createdAt: date), exam: exam)
        let code = data.addDeck(name: "Programming")
        data.deleteDeck(science.id)
        XCTAssertEqual(data.decks.map { $0.id }, [code.id])
        XCTAssertTrue(data.chapters.isEmpty)
        data.deleteDeck(code.id)
        XCTAssertEqual(data.decks.count, 1)
    }

    func testBlankDeckNameBecomesNewDeck() {
        var data = GoldfishData()
        XCTAssertEqual(data.addDeck(name: "   ").name, "New deck")
    }

    func testNewDecksTakeAColourNoDeckUses() {
        var data = GoldfishData()
        let first = data.addDeck(name: "Science")
        let second = data.addDeck(name: "History")
        XCTAssertEqual(first.color, .blue)
        XCTAssertEqual(second.color, .teal)
        XCTAssertEqual(second.initial, "H")
    }

    func testADeckWithAnUnknownColourStillLoads() throws {
        let deck = try JSONDecoder().decode(Deck.self, from: Data(#"{"id":"d1","name":"art","color":"orange"}"#.utf8))
        XCTAssertEqual(deck.color, .blue)
        XCTAssertEqual(deck.initial, "A")
    }
}

final class FireStreakTests: XCTestCase {
    private let today = Day(index: 500)

    private func days(_ ago: Int...) -> [Day] {
        ago.map { today.adding(-$0) }
    }

    func testNeverTaughtIsOut() {
        XCTAssertEqual(FireStreak.compute([], today: today), FireStreak(flame: .out, days: 0, best: 0))
    }

    func testTaughtTodayIsLit() {
        XCTAssertEqual(FireStreak.compute(days(0, 1, 2), today: today), FireStreak(flame: .lit, days: 3, best: 3))
    }

    func testOneMissedDayInsideARunIsForgiven() {
        XCTAssertEqual(FireStreak.compute(days(0, 2, 3), today: today), FireStreak(flame: .lit, days: 3, best: 3))
    }

    func testTaughtYesterdayIsWaiting() {
        XCTAssertEqual(FireStreak.compute(days(1, 2), today: today), FireStreak(flame: .waiting, days: 2, best: 2))
    }

    func testOneMissedDayLeavesEmbersAndKeepsTheCount() {
        XCTAssertEqual(FireStreak.compute(days(2, 3, 4), today: today), FireStreak(flame: .embers, days: 3, best: 3))
    }

    func testTwoMissedDaysPutTheFireOutButKeepTheBest() {
        XCTAssertEqual(FireStreak.compute(days(3, 4, 5, 6), today: today), FireStreak(flame: .out, days: 0, best: 4))
    }

    func testANewFireStartsAfterAGap() {
        XCTAssertEqual(FireStreak.compute(days(0, 1, 5, 6, 7, 8), today: today), FireStreak(flame: .lit, days: 2, best: 4))
    }

    func testRepeatedAndFutureDaysDoNotCount() {
        let taught = days(0, 0, 1) + [today.adding(3)]
        XCTAssertEqual(FireStreak.compute(taught, today: today), FireStreak(flame: .lit, days: 2, best: 2))
    }
}

final class TutorTests: XCTestCase {
    private let date = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private var index: PassageIndex { PassageIndex(chapters: [SampleChapter.chapter(createdAt: date)]) }
    private var exam: Exam { SampleChapter.exam(compiledAt: date) }

    func testPassagesKeepSentencesWholeAndStartAtHeadings() {
        let passages = index.passages
        XCTAssertGreaterThan(passages.count, 4)
        for passage in passages {
            for sentence in TextTools.sentences(passage.text) {
                XCTAssertTrue(TextTools.containsWords(SampleChapter.text, sentence), "not in the chapter: \(sentence)")
            }
        }
        XCTAssertTrue(passages.contains { $0.text.hasPrefix("The swim bladder") })
        XCTAssertTrue(passages.contains { $0.text.hasPrefix("Living in fresh water") })
    }

    func testSearchFindsThePassageThatAnswersTheQuestion() {
        XCTAssertTrue(index.search("Why does water seep into a goldfish by osmosis?").first?.text.contains("osmosis") ?? false)
        XCTAssertTrue(index.search("what protects the gills").first?.text.contains("operculum") ?? false)
    }

    func testSearchFindsNothingForAnotherSubject() {
        XCTAssertTrue(index.search("What is a for loop?").isEmpty)
    }

    func testParserReadsTheReplyFormat() {
        let passages = index.search("osmosis water")
        XCTAssertGreaterThanOrEqual(passages.count, 2)
        let reply = TutorReplyParser.parse("HINT: Compare what is inside the fish with the water.\nASK: Which side has more salt?\nPASSAGE: 2", passages: passages)
        XCTAssertEqual(reply?.hint, "Compare what is inside the fish with the water.")
        XCTAssertEqual(reply?.ask, "Which side has more salt?")
        XCTAssertEqual(reply?.passage, passages[1])
    }

    func testParserToleratesMarkdownAndAWrongPassageNumber() {
        let passages = Array(index.passages.prefix(2))
        let reply = TutorReplyParser.parse("**Hint:** Think about the flap.\n**Ask:** What does it cover?\nPassage: 9", passages: passages)
        XCTAssertEqual(reply?.hint, "Think about the flap.")
        XCTAssertEqual(reply?.ask, "What does it cover?")
        XCTAssertEqual(reply?.passage, passages[0])
    }

    func testParserRejectsAReplyWithoutTheFormat() {
        XCTAssertNil(TutorReplyParser.parse("Osmosis is when water moves into the fish.", passages: []))
    }

    func testGuardReplacesAGivenAwayAnswer() {
        let reply = TutorReply(hint: "They are called lamellae.", ask: "Where are the lamellae?", passage: nil)
        let checked = AnswerGuard.check(reply, question: "What are the folds on gill filaments called?", examQuestions: exam.questions)
        XCTAssertEqual(checked.hint, AnswerGuard.safeHint)
        XCTAssertEqual(checked.ask, AnswerGuard.safeAsk)
    }

    func testGuardLeavesARealHintAlone() {
        let reply = TutorReply(hint: "Look at what covers each filament.", ask: "What do the folds do for the gills?", passage: nil)
        let checked = AnswerGuard.check(reply, question: "What are the folds on gill filaments called?", examQuestions: exam.questions)
        XCTAssertEqual(checked, reply)
    }

    func testScriptedTutorPointsToTheBestPassage() {
        let passages = index.search("what protects the gills")
        let reply = ScriptedTutor.reply(question: "what protects the gills", passages: passages, fishName: "Finn")
        XCTAssertEqual(reply.passage, passages.first)
        XCTAssertTrue(reply.ask.contains("Finn"))
    }

    func testPromptWithThreePassagesFitsOnDevice() {
        let passages = index.search("oxygen water gills")
        let prompt = TutorPrompt.build(question: "How do gills take oxygen from water?", deckName: "Science", fishName: "Finn", passages: passages)
        XCTAssertTrue(TutorPrompt.fitsOnDevice(prompt))
        XCTAssertTrue(prompt.contains("[1] From \"How a Goldfish Lives Underwater\""))
    }
}
