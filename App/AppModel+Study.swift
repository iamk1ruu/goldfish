import Foundation
import GoldfishCore

/// How a typed answer was graded, and where the grading ran.
struct RecallGrade: Equatable {
    let grade: ShortAnswerGrade
    let tier: FishTier
}

/// Teaching, quizzing and reporting actions.
extension AppModel {
    // MARK: Lessons

    /// Opens the Bowl, starting the first lesson if there is none yet.
    func openTeaching(_ chapterID: String) {
        if data.currentLesson(for: chapterID) == nil {
            data.startLesson(chapterID: chapterID, kind: .first, id: UUID().uuidString, at: now)
            scheduleSave()
        }
        showBowl(chapterID)
    }

    /// A new, empty lesson. The previous one stays hidden until "Compare with last time".
    func startFreshWater(_ chapterID: String) {
        data.startLesson(chapterID: chapterID, kind: .freshWater, id: UUID().uuidString, at: now)
        scheduleSave()
        showBowl(chapterID)
    }

    func updateSection(lessonID: String, conceptID: String, text: String) {
        guard let index = data.lessons.firstIndex(where: { $0.id == lessonID }) else { return }
        data.lessons[index].sections[conceptID] = text
        data.lessons[index].updatedAt = now
        scheduleSave()
    }

    func appendToSection(lessonID: String, conceptID: String, sentence: String) {
        guard let lesson = data.lessons.first(where: { $0.id == lessonID }) else { return }
        let existing = lesson.section(conceptID).trimmingCharacters(in: .whitespacesAndNewlines)
        let addition = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !addition.isEmpty else { return }
        updateSection(lessonID: lessonID, conceptID: conceptID, text: existing.isEmpty ? addition : existing + " " + addition)
    }

    func recordPeek(lessonID: String) {
        guard let index = data.lessons.firstIndex(where: { $0.id == lessonID }) else { return }
        data.lessons[index].peekCount += 1
        scheduleSave()
    }

    /// The part of the chapter that answers a question, in the chapter's own words.
    func passageToRead(chapterID: String, question: Question) -> Passage? {
        guard let chapter = chapter(chapterID) else { return nil }
        return PassageIndex(chapters: [chapter]).passage(holding: question.sourceQuote)
    }

    // MARK: Quizzes

    func cachedAnswer(lessonText: String, question: Question) -> FishAnswer? {
        data.cachedAnswer(lessonText: lessonText, question: question)
    }

    func storeAnswer(_ answer: FishAnswer, lessonText: String, question: Question) {
        data.cache(answer, lessonText: lessonText, question: question)
        if !answer.cached {
            diagnostics.record(ModelCallRecord(
                lane: "fish", tier: answer.tier, modelVersion: answer.modelVersion,
                latencyMs: answer.latencyMs, ok: true, detail: answer.verdict.rawValue
            ))
        }
    }

    func recordFishFailure(_ error: Error) {
        diagnostics.record(ModelCallRecord(
            lane: "fish", tier: nil, modelVersion: "", latencyMs: 0, ok: false, detail: String(describing: error)
        ))
    }

    /// Records a finished quiz. Returns true when it was the first teaching of the day, which lights the fire.
    @discardableResult
    func finishQuiz(_ run: QuizRun) -> Bool {
        guard let lesson = data.lessons.first(where: { $0.id == run.lessonID }), let exam = exam(run.chapterID) else {
            return false
        }
        let taughtAlready = data.teachingDays.contains(today)
        data.record(run: run, lesson: lesson, exam: exam, today: today, calendar: calendar)
        scheduleSave()
        return !taughtAlready && data.teachingDays.contains(today)
    }

    /// The previous lesson's text for one concept, for "Compare with last time".
    func previousSection(chapterID: String, conceptID: String) -> String? {
        guard let current = data.currentLesson(for: chapterID), current.kind == .freshWater,
              let previous = data.previousLesson(for: chapterID)
        else { return nil }
        let text = previous.section(conceptID).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    // MARK: Curious Fish

    func shouldAskCurious(_ chapterID: String) -> Bool {
        data.curiousAsked[chapterID] != today
    }

    func markCuriousAsked(_ chapterID: String) {
        data.curiousAsked[chapterID] = today
        scheduleSave()
    }

    // MARK: Your Turn

    /// Records an unaided answer. Returns true when it made the concept Mastered.
    @discardableResult
    func recordStudentAnswer(_ answer: StudentAnswer, chapterID: String) -> Bool {
        let before = data.conceptState(answer.conceptID)
        data.record(answer, chapterID: chapterID, calendar: calendar)
        scheduleSave()
        return before != .mastered && data.conceptState(answer.conceptID) == .mastered
    }

    /// Graded recall is on only once grading has been shown to work: the Grading Check passed on this
    /// phone, or the team turned it on for everyone in Remote Config after it passed. It needs a real model.
    var gradesRecall: Bool {
        guard firebaseReady, !usesScriptedFish else { return false }
        return settings.shortAnswerGrading || data.gradingCheck?.passed == true
    }

    /// Grades the typed answer, on the phone first. Shown only, never scored.
    func gradeRecall(question: Question, text: String) async -> RecallGrade? {
        guard gradesRecall, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let started = Date()
        do {
            let result = try await FirebaseText.respond(
                to: ShortAnswerPrompt.build(question: question, answer: text),
                route: .hybrid, cloudModel: settings.fishCloudModel
            )
            diagnostics.record(ModelCallRecord(
                lane: "grading", tier: result.tier, modelVersion: result.modelVersion,
                latencyMs: Self.ms(since: started), ok: true, detail: result.text.prefix(20).description
            ))
            return ShortAnswerPrompt.parse(result.text).map { RecallGrade(grade: $0, tier: result.tier) }
        } catch {
            diagnostics.record(ModelCallRecord(
                lane: "grading", tier: nil, modelVersion: "", latencyMs: Self.ms(since: started),
                ok: false, detail: String(describing: error)
            ))
            return nil
        }
    }

    func setRecallGrade(_ grade: ShortAnswerGrade, questionID: String, answeredAt: Date) {
        guard let index = data.studentAnswers.lastIndex(where: { $0.questionID == questionID && $0.answeredAt == answeredAt }) else {
            return
        }
        data.studentAnswers[index].recallGrade = grade
        scheduleSave()
    }

    // MARK: Final exam and Report Card

    /// Stores a draft report straight away, then asks the cloud. If offline, the request waits.
    func finishFinalExam(chapterID: String) async {
        guard let inputs = reportInputs(chapterID) else { return }
        data.reports[chapterID] = ReportBuilder.card(
            chapterID: chapterID, draft: nil, exam: inputs.exam, finalAnswers: inputs.fish,
            studentAnswers: inputs.student, writtenBy: "draft", at: now
        )
        if !data.pendingReports.contains(chapterID) {
            data.pendingReports.append(chapterID)
        }
        scheduleSave()
        await flushPendingReports()
    }

    func flushPendingReports() async {
        guard network.isOnline, !data.pendingReports.isEmpty else { return }
        for chapterID in data.pendingReports {
            guard let inputs = reportInputs(chapterID) else {
                data.pendingReports.removeAll { $0 == chapterID }
                continue
            }
            let started = Date()
            do {
                let draft = try await reportWriter.write(inputs.input)
                data.reports[chapterID] = ReportBuilder.card(
                    chapterID: chapterID, draft: draft, exam: inputs.exam, finalAnswers: inputs.fish,
                    studentAnswers: inputs.student, writtenBy: firebaseReady ? settings.reportModel : "fixture", at: now
                )
                data.pendingReports.removeAll { $0 == chapterID }
                diagnostics.record(ModelCallRecord(
                    lane: "report", tier: .cloud, modelVersion: settings.reportModel,
                    latencyMs: Self.ms(since: started), ok: true
                ))
            } catch {
                diagnostics.record(ModelCallRecord(
                    lane: "report", tier: .cloud, modelVersion: settings.reportModel,
                    latencyMs: Self.ms(since: started), ok: false, detail: String(describing: error)
                ))
            }
        }
        scheduleSave()
    }

    private func reportInputs(_ chapterID: String) -> (input: ReportInput, exam: Exam, fish: [FishAnswer], student: [StudentAnswer])? {
        guard let chapter = chapter(chapterID), let exam = exam(chapterID),
              let run = data.latestRun(for: chapterID, kinds: [.finalExam])
        else { return nil }
        let student = data.studentAnswers.filter {
            $0.isFinal && $0.answeredAt >= run.startedAt && exam.question($0.questionID) != nil
        }
        let lessonText = data.lessons.first(where: { $0.id == run.lessonID }).map { fishText(for: $0) } ?? ""
        let input = ReportBuilder.input(
            fishName: fishName, chapter: chapter, exam: exam, lessonText: lessonText,
            finalAnswers: run.answers, studentAnswers: student
        )
        return (input, exam, run.answers, student)
    }
}
