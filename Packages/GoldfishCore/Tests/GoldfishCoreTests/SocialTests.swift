import XCTest
@testable import GoldfishCore

/// Codes, shared chapters, profiles and teach-offs. Everything the cloud stores is one of
/// these Codable types as JSON, so these tests cover what Firestore holds without needing Firebase.
final class ShareCodeTests: XCTestCase {
    func testCodesUseOnlyTheUnambiguousAlphabet() {
        var generator = TestGenerator(seed: 7)
        for _ in 0..<200 {
            let code = ShareCode.make(length: ShareCode.chapterLength, using: &generator)
            XCTAssertTrue(ShareCode.isValid(code, length: ShareCode.chapterLength), code)
            XCTAssertFalse(code.contains { "0O1IL".contains($0) }, code)
        }
    }

    func testNormalizeDropsDashesSpacesAndCase() {
        XCTAssertEqual(ShareCode.normalize(" abc-def "), "ABCDEF")
        XCTAssertTrue(ShareCode.isValid(ShareCode.normalize("abc-def"), length: ShareCode.friendLength))
    }

    func testAMisreadCharacterMakesTheCodeInvalidInsteadOfAnotherCode() {
        // "O" is never in a code, so it is dropped and the code is too short.
        XCTAssertFalse(ShareCode.isValid(ShareCode.normalize("ABC-DEO"), length: ShareCode.friendLength))
    }

    func testDisplaySplitsTheCodeInHalf() {
        XCTAssertEqual(ShareCode.display("ABCDEF"), "ABC-DEF")
        XCTAssertEqual(ShareCode.display("ABCDEFGH"), "ABCD-EFGH")
    }

    func testFindsTheCodeInAPastedMessage() {
        let message = "Learn \"How a Goldfish Lives\" with me on Goldfish. Open the Friends tab and enter the code ABCD-EFGH."
        XCTAssertEqual(ShareCode.find(in: message, length: ShareCode.chapterLength), "ABCDEFGH")
        XCTAssertEqual(ShareCode.find(in: "abcd efgh", length: ShareCode.chapterLength), "ABCDEFGH")
        XCTAssertNil(ShareCode.find(in: "no code here", length: ShareCode.chapterLength))
    }
}

final class SharedChapterTests: XCTestCase {
    private let date = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func sample() -> SharedChapter {
        var chapter = SampleChapter.chapter(createdAt: date)
        chapter.examDate = date
        chapter.deckID = "my-deck"
        return SharedChapter.make(code: "ABCDEFGH", ownerName: "Sam", chapter: chapter, exam: SampleChapter.exam(compiledAt: date), at: date)
    }

    func testSharingLeavesOutTheDeckAndExamDate() {
        let shared = sample()
        XCTAssertNil(shared.chapter.examDate)
        XCTAssertNil(shared.chapter.deckID)
    }

    func testRoundTripsThroughJSON() throws {
        let shared = sample()
        let decoded = try SocialJSON.decode(SharedChapter.self, from: SocialJSON.encode(shared))
        XCTAssertEqual(decoded.chapter.id, shared.chapter.id)
        XCTAssertEqual(decoded.exam.questions, shared.exam.questions)
        XCTAssertEqual(decoded.ownerName, "Sam")
    }

    func testTheSampleFitsInAFirestoreDocument() throws {
        XCTAssertLessThan(try SocialJSON.encode(sample()).utf8.count, SharedChapter.maxBytes)
    }

    func testAValidShareHasNoProblems() {
        XCTAssertEqual(sample().problems(), [])
    }

    func testTamperedSharesAreRefused() {
        var wrongChapter = sample()
        wrongChapter.exam.chapterID = "someone-else"
        XCTAssertFalse(wrongChapter.problems().isEmpty)

        var badQuestion = sample()
        badQuestion.exam.questions[0].correctIndex = 9
        XCTAssertFalse(badQuestion.problems().isEmpty)

        var newer = sample()
        newer.version = SharedChapter.currentVersion + 1
        XCTAssertFalse(newer.problems().isEmpty)

        var empty = sample()
        empty.chapter.sourceText = " "
        XCTAssertFalse(empty.problems().isEmpty)
    }

    func testImportingPutsItInTheFriendsDeckAndCreditsTheSharer() {
        let imported = sample().importedChapter(deckID: "friend-deck", at: date)
        XCTAssertEqual(imported.deckID, "friend-deck")
        XCTAssertEqual(imported.sharedBy, "Sam")
        XCTAssertEqual(imported.shareCode, "ABCDEFGH")
        XCTAssertEqual(imported.id, SampleChapter.id)
    }

    func testOldChaptersWithoutShareFieldsStillLoad() throws {
        let old = #"{"id":"c1","title":"T","sourceText":"Text.","createdAt":0,"isSample":false}"#
        let chapter = try JSONDecoder().decode(Chapter.self, from: Data(old.utf8))
        XCTAssertNil(chapter.sharedBy)
        XCTAssertNil(chapter.shareCode)
    }
}

final class ProfileTests: XCTestCase {
    private let date = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func testNamesAreTrimmedCollapsedAndCapped() {
        XCTAssertEqual(PublicProfile.cleanName("  Sam   Lee \n"), "Sam Lee")
        XCTAssertEqual(PublicProfile.cleanName(String(repeating: "a", count: 40)).count, PublicProfile.maxNameLength)
        XCTAssertEqual(PublicProfile.cleanName("   "), "")
    }

    func testProfileCarriesTheFireAndMasteredCountButNoLessons() throws {
        var data = GoldfishData()
        data.fishName = "Bubbles"
        let today = Day(index: 100)
        data.teachingDays = [Day(index: 98), Day(index: 99), today]
        let profile = PublicProfile.make(uid: "u1", displayName: "Sam", friendCode: "ABCDEF", data: data, today: today, at: date)
        XCTAssertEqual(profile.fishName, "Bubbles")
        XCTAssertEqual(profile.fire.flame, .lit)
        XCTAssertEqual(profile.fire.days, 3)
        XCTAssertEqual(profile.mastered, 0)
        let json = try SocialJSON.encode(profile)
        XCTAssertFalse(json.contains("sections"))
    }

    func testSettingsAndProfileStateSurviveSaving() throws {
        var data = GoldfishData()
        data.preferences = Preferences(sounds: false, haptics: true)
        data.social = SocialState(uid: "u1", displayName: "Sam", friendCode: "ABCDEF")
        data.sharedCodes["sample"] = "ABCDEFGH"
        let loaded = try JSONDecoder().decode(GoldfishData.self, from: JSONEncoder().encode(data))
        XCTAssertEqual(loaded.preferences, data.preferences)
        XCTAssertEqual(loaded.social, data.social)
        XCTAssertEqual(loaded.sharedCodes, data.sharedCodes)
    }

    func testOlderFilesGetDefaultPreferencesAndNoProfile() throws {
        let loaded = try JSONDecoder().decode(GoldfishData.self, from: Data("{}".utf8))
        XCTAssertEqual(loaded.preferences, Preferences())
        XCTAssertNil(loaded.social)
        XCTAssertEqual(loaded.sharedCodes, [:])
    }
}

final class TeachOffTests: XCTestCase {
    private let date = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private var exam: Exam { SampleChapter.exam(compiledAt: date) }

    private func answers(_ questions: [Question], right: (Int) -> Bool, tier: FishTier = .onDevice) -> [FishAnswer] {
        questions.enumerated().map { index, question in
            FishAnswer(
                questionID: question.id, choice: .option(question.correctIndex), quote: "",
                verdict: right(index) ? .correct : .gap, traceSentence: nil, tier: tier,
                modelVersion: "test", latencyMs: 0, raw: ""
            )
        }
    }

    func testATeachOffAsksEveryPracticeQuestionInConceptOrder() {
        let questions = TeachOff.questions(exam: exam)
        XCTAssertEqual(questions.count, exam.questions(in: .practice).count)
        XCTAssertTrue(questions.allSatisfy { $0.pool == .practice })
        let order = questions.map { exam.conceptIndex($0.conceptID) }
        XCTAssertEqual(order, order.sorted())
    }

    func testScoreKeepsOnlyVerdictsAndTiers() {
        let questions = TeachOff.questions(exam: exam)
        let score = TeachOff.score(answers: answers(questions, right: { $0 % 2 == 0 }), at: date)
        XCTAssertEqual(score.total, questions.count)
        XCTAssertEqual(score.right, (questions.count + 1) / 2)
        XCTAssertEqual(score.onDevice, questions.count)
        XCTAssertEqual(score.cloud, 0)
    }

    func testComparisonCountsEachIdeaForBothLessons() {
        let questions = TeachOff.questions(exam: exam)
        let firstConcept = questions[0].conceptID
        let mine = TeachOff.score(answers: answers(questions, right: { _ in true }), at: date)
        let theirs = TeachOff.score(answers: answers(questions, right: { questions[$0].conceptID != firstConcept }), at: date)
        let comparison = TeachOff.compare(mine: mine, theirs: theirs, exam: exam)
        XCTAssertEqual(comparison.total, questions.count)
        XCTAssertEqual(comparison.mine, questions.count)
        XCTAssertGreaterThan(comparison.mine, comparison.theirs)
        XCTAssertEqual(comparison.yoursClearer.map { $0.id }, [firstConcept])
        XCTAssertTrue(comparison.theirsClearer.isEmpty)
    }

    func testComparisonUsesOnlyQuestionsBothFishAnswered() {
        let questions = TeachOff.questions(exam: exam)
        let mine = TeachOff.score(answers: answers(questions, right: { _ in true }), at: date)
        // Their phone dropped the first question in a fair exam check before the teach-off.
        let theirs = TeachOff.score(answers: answers(Array(questions.dropFirst()), right: { _ in true }), at: date)
        let comparison = TeachOff.compare(mine: mine, theirs: theirs, exam: exam)
        XCTAssertEqual(comparison.total, questions.count - 1)
        XCTAssertEqual(comparison.mine, comparison.theirs)
    }

    func testFinnIsKindWhicheverLessonWon() {
        let questions = TeachOff.questions(exam: exam)
        let all = TeachOff.score(answers: answers(questions, right: { _ in true }), at: date)
        let half = TeachOff.score(answers: answers(questions, right: { $0 % 2 == 0 }), at: date)
        let lost = TeachOff.finnLine(TeachOff.compare(mine: half, theirs: all, exam: exam), fishName: "Finn", friendName: "Maya")
        let won = TeachOff.finnLine(TeachOff.compare(mine: all, theirs: half, exam: exam), fishName: "Finn", friendName: "Maya")
        let tie = TeachOff.finnLine(TeachOff.compare(mine: all, theirs: all, exam: exam), fishName: "Finn", friendName: "Maya")
        XCTAssertTrue(lost.contains("Maya"))
        XCTAssertFalse(lost.lowercased().contains("lose"))
        XCTAssertFalse(won.isEmpty)
        XCTAssertTrue(tie.contains("same"))
    }

    func testChallengeKnowsTheOtherSide() {
        let challenge = Challenge(
            id: "c", chapterCode: "ABCDEFGH", chapterID: "ch", chapterTitle: "T",
            fromUid: "a", fromName: "Ana", toUid: "b", toName: "Ben", createdAt: date
        )
        XCTAssertEqual(challenge.other(than: "a").name, "Ben")
        XCTAssertEqual(challenge.other(than: "b").name, "Ana")
    }
}

/// A small seeded generator so code tests are repeatable.
private struct TestGenerator: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
