import Foundation
import GoldfishCore

/// Fixture data for `scripts/screenshots.sh`. Nothing here is saved, and every fish answer
/// comes from the scripted stand-in, so the badges read "Scripted".
extension AppModel {
    func applyFixture(screen: String) {
        let date = now
        var fixture = GoldfishData()
        fixture.onboarded = screen != "onboarding"
        let exam = SampleChapter.exam(compiledAt: date)
        fixture.addChapter(SampleChapter.chapter(createdAt: date), exam: exam)

        var lesson = fixture.startLesson(chapterID: SampleChapter.id, kind: .first, id: "fixture-lesson", at: date)
        lesson.sections = SampleChapter.fixtureSections(exam: exam)
        lesson.peekCount = 1
        fixture.updateLesson(lesson)

        let lessonText = LessonComposer.fishText(
            lesson: lesson, concepts: exam.concepts, checker: OwnWordsChecker(chapterText: SampleChapter.text)
        )
        let questions = QuizPicker.fishRound(exam: exam, stats: [:])
        let answers = questions.map { question -> FishAnswer in
            let reply = ScriptedFishEngine.answer(question: question, lesson: lessonText)
            let parsed = FishReplyParser.parse(reply, optionCount: question.options.count)
            let grade = FishGrader.grade(parsed, question: question, lesson: lessonText)
            return FishAnswer(
                questionID: question.id, choice: parsed?.choice ?? .notTaught, quote: parsed?.quote ?? "",
                verdict: grade.verdict, traceSentence: grade.traceSentence, tier: .scripted,
                modelVersion: "scripted-fish", latencyMs: 900, raw: reply, note: grade.note
            )
        }
        let run = QuizRun(
            id: "fixture-run", chapterID: SampleChapter.id, lessonID: lesson.id, kind: .pop,
            lessonHash: AnswerCacheKey.lessonHash(lessonText), answers: answers, predictedScore: 6,
            startedAt: date, finishedAt: date
        )
        fixture.record(run: run, lesson: lesson, exam: exam, today: today, calendar: calendar)

        for (index, question) in exam.questions(in: .yourTurn).prefix(4).enumerated() {
            let correct = index != 3
            fixture.record(StudentAnswer(
                questionID: question.id, conceptID: question.conceptID, recallText: "",
                chosenIndex: correct ? question.correctIndex : (question.correctIndex + 1) % 4,
                sure: true, correct: correct, answeredAt: date, day: today
            ), chapterID: SampleChapter.id)
        }

        fixture.reports[SampleChapter.id] = ReportBuilder.card(
            chapterID: SampleChapter.id,
            draft: ReportDraft(
                explainedWell: ["Your gills section walked the fish from mouth to operculum clearly."],
                misconceptions: ["You wrote that adding gas makes a fish sink. Adding gas makes it rise."],
                reviewNext: ["The lateral line was never taught.", "Temperature and oxygen is still empty."]
            ),
            exam: exam, finalAnswers: Array(answers.prefix(6)), studentAnswers: fixture.studentAnswers,
            writtenBy: "fixture", at: date
        )

        // A made-up profile. FixtureSocialBackend supplies the friends.
        if screen == "friends" || screen == "teachoff" {
            fixture.social = SocialState(uid: "me", displayName: "Sam", friendCode: "SAM234")
            fixture.sharedCodes[SampleChapter.id] = "SAMPLE23"
            tab = .friends
        }

        data = fixture
        path = fixturePath(screen)
    }

    private func fixturePath(_ screen: String) -> [Route] {
        let id = SampleChapter.id
        switch screen {
        case "chapter": return [.chapter(id)]
        case "teach": return [.chapter(id), .teach(id)]
        case "quiz": return [.chapter(id), .teach(id), .quiz(id, .pop)]
        case "review": return [.chapter(id), .review(id)]
        case "yourturn": return [.chapter(id), .yourTurn(id)]
        case "final": return [.chapter(id), .finalExam(id)]
        case "report": return [.chapter(id), .report(id)]
        case "map": return [.chapter(id), .map(id)]
        case "settings": return [.settings]
        case "diagnostics": return [.settings, .diagnostics]
        case "teachoff": return [.teachOff("fixture-teachoff")]
        default: return []
        }
    }
}
