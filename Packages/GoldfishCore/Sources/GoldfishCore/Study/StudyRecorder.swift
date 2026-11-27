import Foundation

/// Applies study events to the stored data. Kept here, not in the app, so every rule is testable.
extension GoldfishData {
    public mutating func addChapter(_ chapter: Chapter, exam: Exam) {
        var chapter = chapter
        chapter.deckID = homeDeckID(for: chapter)
        chapters.removeAll { $0.id == chapter.id }
        chapters.append(chapter)
        exams[chapter.id] = exam
        if chapterProgress[chapter.id] == nil {
            chapterProgress[chapter.id] = ChapterProgress(chapterID: chapter.id)
        }
        for concept in exam.concepts where concepts[concept.id] == nil {
            concepts[concept.id] = ConceptProgress(conceptID: concept.id)
        }
    }

    public mutating func deleteChapter(_ chapterID: String) {
        let conceptIDs = Set(exams[chapterID]?.concepts.map { $0.id } ?? [])
        let questionIDs = Set(exams[chapterID]?.questions.map { $0.id } ?? [])
        chapters.removeAll { $0.id == chapterID }
        exams[chapterID] = nil
        lessons.removeAll { $0.chapterID == chapterID }
        quizRuns.removeAll { $0.chapterID == chapterID }
        studentAnswers.removeAll { questionIDs.contains($0.questionID) }
        for id in conceptIDs { concepts[id] = nil }
        for id in questionIDs { questionStats[id] = nil }
        chapterProgress[chapterID] = nil
        reports[chapterID] = nil
        pendingReports.removeAll { $0 == chapterID }
        curiousAsked[chapterID] = nil
    }

    /// Starts a new lesson. A Fresh Water lesson starts empty: the old one stays hidden.
    @discardableResult
    public mutating func startLesson(chapterID: String, kind: LessonKind, id: String, at date: Date) -> Lesson {
        let lesson = Lesson(id: id, chapterID: chapterID, kind: kind, createdAt: date)
        lessons.append(lesson)
        return lesson
    }

    public mutating func updateLesson(_ lesson: Lesson) {
        if let index = lessons.firstIndex(where: { $0.id == lesson.id }) {
            lessons[index] = lesson
        } else {
            lessons.append(lesson)
        }
    }

    public func examDay(for chapterID: String, calendar: Calendar = .current) -> Day? {
        chapter(chapterID)?.examDate.map { Day($0, calendar: calendar) }
    }

    public mutating func setExamDate(_ date: Date?, for chapterID: String, calendar: Calendar = .current) {
        guard let index = chapters.firstIndex(where: { $0.id == chapterID }) else { return }
        chapters[index].examDate = date
        if let progress = chapterProgress[chapterID] {
            var updated = progress
            updated.nextDueOn = Tides.nextFreshWater(progress, examDay: examDay(for: chapterID, calendar: calendar))
            chapterProgress[chapterID] = updated
        }
    }

    /// Stores one fish answer in the cache, so the same lesson and question are never re-asked.
    public mutating func cache(_ answer: FishAnswer, lessonText: String, question: Question) {
        var stored = answer
        stored.cached = false
        answerCache[AnswerCacheKey.key(lesson: lessonText, question: question)] = stored
    }

    public func cachedAnswer(lessonText: String, question: Question) -> FishAnswer? {
        guard var answer = answerCache[AnswerCacheKey.key(lesson: lessonText, question: question)] else {
            return nil
        }
        answer.cached = true
        answer.latencyMs = 0
        return answer
    }

    /// Applies a finished quiz: question stats, concept levels, the chapter schedule and the streak.
    public mutating func record(run: QuizRun, lesson: Lesson, exam: Exam, today: Day, calendar: Calendar = .current) {
        quizRuns.removeAll { $0.id == run.id }
        quizRuns.append(run)

        for answer in run.answers {
            var stat = questionStats[answer.questionID] ?? QuestionStat()
            if !answer.cached {
                stat.timesAsked += 1
                if answer.verdict != .correct {
                    stat.timesMissed += 1
                }
            }
            stat.lastVerdict = answer.verdict
            questionStats[answer.questionID] = stat
        }

        for concept in exam.concepts {
            let answers = run.answers.filter { exam.question($0.questionID)?.conceptID == concept.id }
            guard !answers.isEmpty else { continue }
            let progress = concepts[concept.id] ?? ConceptProgress(conceptID: concept.id)
            concepts[concept.id] = MasteryRules.afterQuiz(
                progress, answers: answers, writtenFromMemory: lesson.writtenFromMemory
            )
        }

        if run.kind != .finalExam {
            let progress = chapterProgress[run.chapterID] ?? ChapterProgress(chapterID: run.chapterID)
            chapterProgress[run.chapterID] = Tides.recordSession(
                progress, kind: lesson.kind, on: today, examDay: examDay(for: run.chapterID, calendar: calendar)
            )
            if !teachingDays.contains(today) {
                teachingDays.append(today)
            }
        }
    }

    /// Applies one unaided answer: the Your Turn box, mastery, and "sure but wrong" retries.
    public mutating func record(_ answer: StudentAnswer, chapterID: String, calendar: Calendar = .current) {
        studentAnswers.append(answer)
        let progress = concepts[answer.conceptID] ?? ConceptProgress(conceptID: answer.conceptID)
        let scheduled = Tides.scheduleConcept(
            progress,
            correct: answer.correct,
            sure: answer.sure,
            questionID: answer.questionID,
            today: answer.day,
            examDay: examDay(for: chapterID, calendar: calendar)
        )
        concepts[answer.conceptID] = MasteryRules.afterYourTurn(scheduled, correct: answer.correct, day: answer.day)
    }

    /// Your Turn questions due today, across one chapter.
    public func dueConceptCount(chapterID: String, today: Day) -> Int {
        guard let exam = exams[chapterID] else { return 0 }
        return exam.concepts.filter { Tides.isDue(concepts[$0.id], today: today) }.count
    }
}
