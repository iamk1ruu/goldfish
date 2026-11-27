import XCTest
@testable import GoldfishCore

final class TidesTests: XCTestCase {
    private let start = Day(index: 1000)

    func testDefaultFreshWaterGaps() {
        var progress = Tides.recordSession(ChapterProgress(chapterID: "ch"), kind: .first, on: start, examDay: nil)
        XCTAssertEqual(progress.nextDueOn, start.adding(1))
        progress = Tides.recordSession(progress, kind: .freshWater, on: start.adding(1), examDay: nil)
        XCTAssertEqual(progress.nextDueOn, start.adding(3))
        progress = Tides.recordSession(progress, kind: .freshWater, on: start.adding(3), examDay: nil)
        XCTAssertEqual(progress.nextDueOn, start.adding(7))
        progress = Tides.recordSession(progress, kind: .freshWater, on: start.adding(7), examDay: nil)
        XCTAssertEqual(progress.nextDueOn, start.adding(14))
        progress = Tides.recordSession(progress, kind: .freshWater, on: start.adding(14), examDay: nil)
        XCTAssertEqual(progress.nextDueOn, start.adding(28))
    }

    func testLateSessionIsNeverScheduledInThePast() {
        var progress = Tides.recordSession(ChapterProgress(chapterID: "ch"), kind: .first, on: start, examDay: nil)
        progress = Tides.recordSession(progress, kind: .freshWater, on: start.adding(5), examDay: nil)
        XCTAssertEqual(progress.nextDueOn, start.adding(6))
    }

    func testFreshWaterCountsOncePerDay() {
        var progress = Tides.recordSession(ChapterProgress(chapterID: "ch"), kind: .first, on: start, examDay: nil)
        progress = Tides.recordSession(progress, kind: .freshWater, on: start.adding(1), examDay: nil)
        progress = Tides.recordSession(progress, kind: .freshWater, on: start.adding(1), examDay: nil)
        XCTAssertEqual(progress.freshWaterDone, 1)
    }

    func testExamDateCompressesTheSchedule() {
        let exam = start.adding(40)
        let progress = Tides.recordSession(ChapterProgress(chapterID: "ch"), kind: .first, on: start, examDay: exam)
        XCTAssertEqual(progress.nextDueOn, start.adding(6), "15% of 40 days")

        let close = Tides.recordSession(ChapterProgress(chapterID: "ch"), kind: .first, on: start, examDay: start.adding(3))
        XCTAssertEqual(close.nextDueOn, start.adding(1))

        let far = Tides.recordSession(ChapterProgress(chapterID: "ch"), kind: .first, on: start, examDay: start.adding(200))
        XCTAssertEqual(far.nextDueOn, start.adding(14), "never more than 14 days")

        let tomorrow = Tides.recordSession(ChapterProgress(chapterID: "ch"), kind: .first, on: start, examDay: start.adding(1))
        XCTAssertNil(tomorrow.nextDueOn)
    }

    func testLastSessionLandsTheDayBeforeTheExam() {
        let progress = ChapterProgress(chapterID: "ch", firstTaughtOn: start, lastSessionOn: start.adding(10))
        XCTAssertEqual(Tides.nextFreshWater(progress, examDay: start.adding(12)), start.adding(11))
    }

    func testYourTurnBoxes() {
        var progress = ConceptProgress(conceptID: "c")
        progress = Tides.scheduleConcept(progress, correct: true, sure: true, questionID: "q", today: start, examDay: nil)
        XCTAssertEqual(progress.box, 1)
        XCTAssertEqual(progress.dueOn, start.adding(3))

        let sameDay = Tides.scheduleConcept(progress, correct: true, sure: true, questionID: "q2", today: start, examDay: nil)
        XCTAssertEqual(sameDay.box, 1, "moves up at most once a day")

        progress = Tides.scheduleConcept(progress, correct: true, sure: nil, questionID: "q", today: start.adding(3), examDay: nil)
        XCTAssertEqual(progress.dueOn, start.adding(10))

        progress = Tides.scheduleConcept(progress, correct: false, sure: false, questionID: "q", today: start.adding(10), examDay: nil)
        XCTAssertEqual(progress.box, 0)
        XCTAssertEqual(progress.dueOn, start.adding(11))
        XCTAssertEqual(progress.retryQuestionIDs, [])
    }

    func testSureButWrongIsDueTomorrowAndAskedFirst() {
        var progress = ConceptProgress(conceptID: "c", box: 3)
        progress = Tides.scheduleConcept(progress, correct: false, sure: true, questionID: "q", today: start, examDay: nil)
        XCTAssertEqual(progress.dueOn, start.adding(1))
        XCTAssertEqual(progress.retryQuestionIDs, ["q"])
        progress = Tides.scheduleConcept(progress, correct: true, sure: true, questionID: "q", today: start.adding(1), examDay: nil)
        XCTAssertEqual(progress.retryQuestionIDs, [])
    }

    func testStreakWeek() {
        let days = [start, start.adding(-2), start.adding(-9)]
        XCTAssertEqual(Streak.week(days, endingOn: start), [false, false, false, false, true, false, true])
        XCTAssertEqual(Streak.count(days, endingOn: start), 2)
    }

    func testDayFromDates() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let morning = calendar.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 8))!
        let night = calendar.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 23))!
        let next = calendar.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 0, minute: 30))!
        XCTAssertEqual(Day(morning, calendar: calendar), Day(night, calendar: calendar))
        XCTAssertEqual(Day(morning, calendar: calendar).days(until: Day(next, calendar: calendar)), 1)
        XCTAssertEqual(Day(Day(morning, calendar: calendar).date(calendar: calendar), calendar: calendar), Day(morning, calendar: calendar))
    }
}

final class MasteryTests: XCTestCase {
    private let day = Day(index: 500)

    func testStatesFromTheFish() {
        XCTAssertEqual(MasteryRules.state(nil), .notTaught)
        let progress = ConceptProgress(conceptID: "c")
        let right = FishAnswer(questionID: "q", choice: .option(0), quote: "", verdict: .correct, traceSentence: nil,
                               tier: .scripted, modelVersion: "", latencyMs: 0, raw: "")
        var wrong = right
        wrong.verdict = .gap

        XCTAssertEqual(MasteryRules.state(MasteryRules.afterQuiz(progress, answers: [right, wrong], writtenFromMemory: false)), .notTaught)
        let taught = MasteryRules.afterQuiz(progress, answers: [right], writtenFromMemory: false)
        XCTAssertEqual(MasteryRules.state(taught), .taught)
        let recalled = MasteryRules.afterQuiz(taught, answers: [right], writtenFromMemory: true)
        XCTAssertEqual(MasteryRules.state(recalled), .recalled)
        XCTAssertEqual(MasteryRules.state(MasteryRules.afterQuiz(recalled, answers: [right], writtenFromMemory: false)), .recalled,
                       "a later first-style quiz never lowers the level")
    }

    func testMasteryNeedsThreeDifferentDays() {
        var progress = ConceptProgress(conceptID: "c", fishLevel: .taught)
        progress = MasteryRules.afterYourTurn(progress, correct: true, day: day)
        progress = MasteryRules.afterYourTurn(progress, correct: true, day: day)
        progress = MasteryRules.afterYourTurn(progress, correct: true, day: day.adding(1))
        XCTAssertNotEqual(MasteryRules.state(progress), .mastered)
        progress = MasteryRules.afterYourTurn(progress, correct: true, day: day.adding(3))
        XCTAssertEqual(MasteryRules.state(progress), .mastered)
    }

    func testMissSlipsMasteredBackToRecalled() {
        var progress = ConceptProgress(conceptID: "c", fishLevel: .taught, correctDays: [day, day.adding(1), day.adding(2)])
        XCTAssertEqual(MasteryRules.state(progress), .mastered)
        progress = MasteryRules.afterYourTurn(progress, correct: false, day: day.adding(5))
        XCTAssertEqual(MasteryRules.state(progress), .recalled)
        XCTAssertEqual(progress.correctDays, [])
        for offset in 6...8 {
            progress = MasteryRules.afterYourTurn(progress, correct: true, day: day.adding(offset))
        }
        XCTAssertEqual(MasteryRules.state(progress), .mastered)
        XCTAssertFalse(progress.slipped)
    }

    func testMissBeforeMasteryRestartsTheCount() {
        var progress = ConceptProgress(conceptID: "c", correctDays: [day, day.adding(1)])
        progress = MasteryRules.afterYourTurn(progress, correct: false, day: day.adding(2))
        XCTAssertEqual(progress.correctDays, [])
        XCTAssertFalse(progress.slipped)
    }
}

final class QuizPickerTests: XCTestCase {
    private let exam = SampleChapter.exam(compiledAt: Date(timeIntervalSince1970: 0))

    func testFreshPopQuizCoversEveryConceptFirst() {
        let picked = QuizPicker.popQuiz(exam: exam, stats: [:], count: 8)
        XCTAssertEqual(picked.count, 8)
        XCTAssertEqual(Set(picked.prefix(6).map { $0.conceptID }).count, 6)
        XCTAssertTrue(picked.allSatisfy { $0.pool == .practice })
        XCTAssertEqual(Set(picked.map { $0.id }).count, 8, "no repeats")
    }

    func testMissedQuestionsComeFirstThenUntestedConcepts() {
        let stats: [String: QuestionStat] = [
            "sample.c1.p1": QuestionStat(timesAsked: 1, timesMissed: 0, lastVerdict: .correct),
            "sample.c2.p1": QuestionStat(timesAsked: 1, timesMissed: 1, lastVerdict: .gap),
        ]
        let picked = QuizPicker.popQuiz(exam: exam, stats: stats, count: 8)
        XCTAssertEqual(picked.first?.id, "sample.c2.p1")
        XCTAssertEqual(Set(picked.dropFirst().prefix(4).map { $0.conceptID }), ["sample.c3", "sample.c4", "sample.c5", "sample.c6"])

        let recheck = QuizPicker.popQuiz(exam: exam, stats: stats, count: 8, onlyMissed: true)
        XCTAssertEqual(recheck.map { $0.id }, ["sample.c2.p1"])
    }

    func testYourTurnPutsRetriesAndDueConceptsFirst() {
        let today = Day(index: 100)
        let progress: [String: ConceptProgress] = [
            "sample.c5": ConceptProgress(conceptID: "sample.c5", dueOn: today.adding(-1), retryQuestionIDs: []),
            "sample.c6": ConceptProgress(conceptID: "sample.c6", dueOn: today.adding(5), retryQuestionIDs: ["sample.c6.y1"]),
            "sample.c1": ConceptProgress(conceptID: "sample.c1", dueOn: today.adding(5)),
        ]
        let picked = QuizPicker.yourTurn(exam: exam, progress: progress, history: [], today: today, count: 5)
        XCTAssertEqual(picked.map { $0.id }.prefix(2), ["sample.c6.y1", "sample.c5.y1"])
        XCTAssertTrue(picked.allSatisfy { $0.pool == .yourTurn })
        XCTAssertFalse(picked.map { $0.id }.contains("sample.c1.y1"), "not due, so it comes after concepts never tried")
    }

    func testFinalExamUsesOnlyHeldOutQuestions() {
        let final = QuizPicker.finalExam(exam: exam)
        XCTAssertEqual(final.count, 6)
        XCTAssertTrue(final.allSatisfy { $0.pool == .finalExam })
    }
}

final class RecorderAndStoreTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    private func answer(_ id: String, _ verdict: FishVerdict, cached: Bool = false) -> FishAnswer {
        FishAnswer(questionID: id, choice: .option(0), quote: "", verdict: verdict, traceSentence: nil,
                   tier: .onDevice, modelVersion: ModelVersion.appleOnDevice, latencyMs: 10, raw: "", cached: cached)
    }

    func testRecordingAQuizUpdatesStatsLevelsScheduleAndStreak() {
        var data = GoldfishData()
        let exam = SampleChapter.exam(compiledAt: date)
        data.addChapter(SampleChapter.chapter(createdAt: date), exam: exam)
        let lesson = data.startLesson(chapterID: SampleChapter.id, kind: .first, id: "l1", at: date)
        let today = Day(date)
        let run = QuizRun(
            id: "r1", chapterID: SampleChapter.id, lessonID: "l1", kind: .pop, lessonHash: "h",
            answers: [answer("sample.c1.p1", .correct), answer("sample.c3.p2", .mixUp), answer("sample.c3.p1", .correct, cached: true)],
            startedAt: date, finishedAt: date
        )
        data.record(run: run, lesson: lesson, exam: exam, today: today)

        XCTAssertEqual(data.questionStats["sample.c1.p1"], QuestionStat(timesAsked: 1, timesMissed: 0, lastVerdict: .correct))
        XCTAssertEqual(data.questionStats["sample.c3.p2"]?.timesMissed, 1)
        XCTAssertEqual(data.questionStats["sample.c3.p1"]?.timesAsked, 0, "cached answers are not new asks")
        XCTAssertEqual(data.conceptState("sample.c1"), .taught)
        XCTAssertEqual(data.conceptState("sample.c3"), .notTaught)
        XCTAssertEqual(data.chapterProgress[SampleChapter.id]?.nextDueOn, today.adding(1))
        XCTAssertEqual(data.teachingDays, [today])
        XCTAssertEqual(data.latestRun(for: SampleChapter.id)?.id, "r1")
    }

    func testAnswerCacheRoundTrip() {
        var data = GoldfishData()
        let question = SampleChapter.exam(compiledAt: date).questions[0]
        data.cache(answer(question.id, .correct), lessonText: "lesson", question: question)
        XCTAssertEqual(data.cachedAnswer(lessonText: "lesson", question: question)?.cached, true)
        XCTAssertNil(data.cachedAnswer(lessonText: "edited lesson", question: question))
    }

    func testRecordingStudentAnswersDrivesMastery() {
        var data = GoldfishData()
        let exam = SampleChapter.exam(compiledAt: date)
        data.addChapter(SampleChapter.chapter(createdAt: date), exam: exam)
        for offset in [0, 1, 2] {
            data.record(StudentAnswer(
                questionID: "sample.c2.y1", conceptID: "sample.c2", recallText: "", chosenIndex: 0, sure: true,
                correct: true, answeredAt: date, day: Day(index: 100 + offset)
            ), chapterID: SampleChapter.id)
        }
        XCTAssertEqual(data.conceptState("sample.c2"), .mastered)
        XCTAssertEqual(data.concepts["sample.c2"]?.box, 3)
    }

    func testDeletingAChapterRemovesItsData() {
        var data = GoldfishData()
        let exam = SampleChapter.exam(compiledAt: date)
        data.addChapter(SampleChapter.chapter(createdAt: date), exam: exam)
        data.startLesson(chapterID: SampleChapter.id, kind: .first, id: "l1", at: date)
        data.deleteChapter(SampleChapter.id)
        XCTAssertTrue(data.chapters.isEmpty)
        XCTAssertTrue(data.lessons.isEmpty)
        XCTAssertTrue(data.concepts.isEmpty)
        XCTAssertNil(data.exams[SampleChapter.id])
    }

    func testCurrentAndPreviousLesson() {
        var data = GoldfishData()
        data.startLesson(chapterID: "ch", kind: .first, id: "old", at: date)
        data.startLesson(chapterID: "ch", kind: .freshWater, id: "new", at: date.addingTimeInterval(60))
        XCTAssertEqual(data.currentLesson(for: "ch")?.id, "new")
        XCTAssertEqual(data.previousLesson(for: "ch")?.id, "old")
    }

    private func temporaryStore() -> JSONStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("goldfish-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("goldfish.json")
        return JSONStore(fileURL: url)
    }

    func testSaveAndReload() throws {
        let store = temporaryStore()
        var data = GoldfishData()
        data.fishName = "Bubbles"
        data.addChapter(SampleChapter.chapter(createdAt: date), exam: SampleChapter.exam(compiledAt: date))
        try store.save(data)
        let loaded = store.load()
        XCTAssertEqual(loaded.outcome, .loaded)
        XCTAssertEqual(loaded.data, data)
    }

    func testMissingFileStartsFresh() {
        let loaded = temporaryStore().load()
        XCTAssertEqual(loaded.outcome, .fresh)
        XCTAssertEqual(loaded.data, GoldfishData())
    }

    func testDamagedFileIsMovedAsideAndAppStartsEmpty() throws {
        let store = temporaryStore()
        try FileManager.default.createDirectory(at: store.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: store.fileURL)
        let loaded = store.load()
        guard case .recovered(let name) = loaded.outcome else {
            return XCTFail("expected recovery, got \(loaded.outcome)")
        }
        XCTAssertTrue(name.hasPrefix("goldfish-damaged-"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
    }

    func testOlderFilesWithMissingKeysStillLoad() throws {
        let data = try JSONDecoder().decode(GoldfishData.self, from: Data(#"{"fishName":"Goldie"}"#.utf8))
        XCTAssertEqual(data.fishName, "Goldie")
        XCTAssertTrue(data.chapters.isEmpty)
    }
}

final class SettingsAndReportTests: XCTestCase {
    func testRemoteValuesApplyWithinRange() {
        var settings = GoldfishSettings()
        settings.apply("400", forKey: "bowl_word_limit")
        settings.apply("99999", forKey: "pop_quiz_length")
        settings.apply("gemini-4-hydrogen", forKey: "exam_model")
        settings.apply("true", forKey: "short_answer_grading")
        settings.apply("", forKey: "fish_cloud_model")
        XCTAssertEqual(settings.bowlWordLimit, 400)
        XCTAssertEqual(settings.popQuizLength, 8)
        XCTAssertEqual(settings.examModel, "gemini-4-hydrogen")
        XCTAssertTrue(settings.shortAnswerGrading)
        XCTAssertEqual(settings.fishCloudModel, "gemini-3.5-flash-lite")
        for key in GoldfishSettings.remoteKeys {
            XCTAssertFalse(settings.value(forKey: key).isEmpty, key)
        }
    }

    func testReportCardCountsComeFromCode() {
        let date = Date(timeIntervalSince1970: 0)
        let exam = SampleChapter.exam(compiledAt: date)
        let finals = QuizPicker.finalExam(exam: exam)
        let fish = finals.enumerated().map { index, question in
            FishAnswer(questionID: question.id, choice: .option(0), quote: "", verdict: index < 4 ? .correct : .mixUp,
                       traceSentence: index < 4 ? nil : "A wrong sentence.", tier: .onDevice, modelVersion: "", latencyMs: 0, raw: "")
        }
        let student = exam.questions(in: .yourTurn).prefix(3).map { question in
            StudentAnswer(questionID: question.id, conceptID: question.conceptID, recallText: "", chosenIndex: question.correctIndex,
                          sure: true, correct: true, answeredAt: date, day: Day(index: 1))
        }
        let card = ReportBuilder.card(chapterID: "sample", draft: nil, exam: exam, finalAnswers: fish,
                                      studentAnswers: Array(student), writtenBy: "gemini", at: date)
        XCTAssertEqual(card.coverageCorrect, 4)
        XCTAssertEqual(card.coverageTotal, 6)
        XCTAssertEqual(card.unaidedCorrect, 3)
        XCTAssertTrue(card.isDraft)
        XCTAssertEqual(card.misconceptions.count, 2)

        let input = ReportBuilder.input(fishName: "Finn", chapter: SampleChapter.chapter(createdAt: date), exam: exam,
                                        lessonText: "lesson", finalAnswers: fish, studentAnswers: Array(student))
        let prompt = CloudPrompts.report(input)
        XCTAssertTrue(prompt.contains("goldfish named Finn"))
        XCTAssertFalse(prompt.contains("Countercurrent exchange is the reason"), "the chapter text is never sent")
    }

    func testRingBufferDropsOldest() {
        var buffer = RingBuffer<Int>(capacity: 3)
        for value in 1...5 { buffer.append(value) }
        XCTAssertEqual(buffer.elements, [3, 4, 5])
    }
}
