import Foundation

/// One card in the student's quiz: a Your Turn question and the chapter it comes from,
/// so a deck-wide quiz can record each answer against the right chapter.
public struct QuizCard: Equatable, Identifiable {
    public let chapterID: String
    public let question: Question

    public init(chapterID: String, question: Question) {
        self.chapterID = chapterID
        self.question = question
    }

    public var id: String {
        question.id
    }
}

/// Chooses which questions a quiz asks.
public enum QuizPicker {
    /// Practice questions for the fish. Questions missed last time come first,
    /// then concepts not yet tested, then the least-asked rest. No repeats within a run.
    public static func popQuiz(
        exam: Exam,
        stats: [String: QuestionStat],
        count: Int,
        onlyMissed: Bool = false
    ) -> [Question] {
        let practice = exam.questions(in: .practice)
        let missed = practice.filter { question in
            guard let verdict = stats[question.id]?.lastVerdict else { return false }
            return verdict != .correct
        }
        if onlyMissed {
            return Array(missed.prefix(count))
        }

        let tested = Set(practice.filter { (stats[$0.id]?.timesAsked ?? 0) > 0 }.map { $0.conceptID })
        let untested = interleave(exam.concepts.filter { !tested.contains($0.id) }.map { concept in
            practice.filter { $0.conceptID == concept.id }
        })
        let rest = interleave(exam.concepts.map { concept in
            leastAskedFirst(practice.filter { $0.conceptID == concept.id }, stats: stats)
        })
        return Array(unique(missed + untested + rest).prefix(count))
    }

    /// Questions for the student that the fish is never asked.
    /// "Sure but wrong" questions first, then concepts that are due, then concepts never tried,
    /// then the rest. Within each group, concepts take turns and older answers come first.
    public static func yourTurn(
        exam: Exam,
        progress: [String: ConceptProgress],
        history: [StudentAnswer],
        today: Day,
        count: Int
    ) -> [Question] {
        let pool = exam.questions(in: .yourTurn)
        var lastAnswered: [String: Date] = [:]
        for answer in history {
            if let seen = lastAnswered[answer.questionID], seen >= answer.answeredAt {
                continue
            }
            lastAnswered[answer.questionID] = answer.answeredAt
        }
        let retry = Set(progress.values.flatMap { $0.retryQuestionIDs })

        func group(_ question: Question) -> Int {
            if retry.contains(question.id) { return 0 }
            guard let due = progress[question.conceptID]?.dueOn else { return 2 }
            return due <= today ? 1 : 3
        }

        var ordered: [Question] = []
        for tier in 0...3 {
            let inTier = pool.filter { group($0) == tier }
            let byConcept = exam.concepts.map { concept in
                inTier.filter { $0.conceptID == concept.id }
                    .enumerated()
                    .sorted { a, b in
                        let da = lastAnswered[a.element.id] ?? .distantPast
                        let db = lastAnswered[b.element.id] ?? .distantPast
                        return da != db ? da < db : a.offset < b.offset
                    }
                    .map { $0.element }
            }
            ordered.append(contentsOf: interleave(byConcept))
        }
        return Array(unique(ordered).prefix(count))
    }

    /// One practice question per concept, so every idea in the chapter is tested in every
    /// round. The quiz is as long as the chapter has concepts. For each concept, a question the fish
    /// missed last time comes first, then the least-asked one.
    public static func fishRound(exam: Exam, stats: [String: QuestionStat]) -> [Question] {
        exam.concepts.compactMap { concept in
            let practice = exam.questions(in: .practice, concept: concept.id)
            let missed = practice.first { question in
                guard let verdict = stats[question.id]?.lastVerdict else { return false }
                return verdict != .correct
            }
            return missed ?? leastAskedFirst(practice, stats: stats).first
        }
    }

    /// The student's quiz cards for one chapter, one per concept so no idea is repeated.
    /// With `everything`, every concept gets a card. Otherwise only concepts that are due, never tried,
    /// or answered wrong while sure. The order is the same as `yourTurn`.
    public static func cards(
        exam: Exam,
        chapterID: String,
        progress: [String: ConceptProgress],
        history: [StudentAnswer],
        today: Day,
        everything: Bool
    ) -> [QuizCard] {
        let retry = Set(progress.values.flatMap { $0.retryQuestionIDs })
        func due(_ question: Question) -> Bool {
            if retry.contains(question.id) { return true }
            guard let dueOn = progress[question.conceptID]?.dueOn else { return true }
            return dueOn <= today
        }
        let ordered = yourTurn(exam: exam, progress: progress, history: history, today: today, count: Int.max)
        var seen = Set<String>()
        var cards: [QuizCard] = []
        for question in ordered where !seen.contains(question.conceptID) {
            guard everything || due(question) else { continue }
            seen.insert(question.conceptID)
            cards.append(QuizCard(chapterID: chapterID, question: question))
        }
        return cards
    }

    /// Mixed Bowl: the due cards from every chapter in a deck, chapters taking turns.
    public static func deckCards(
        exams: [(chapterID: String, exam: Exam)],
        progress: [String: ConceptProgress],
        history: [StudentAnswer],
        today: Day
    ) -> [QuizCard] {
        let perChapter = exams.map { entry in
            cards(exam: entry.exam, chapterID: entry.chapterID, progress: progress, history: history, today: today, everything: false)
        }
        var result: [QuizCard] = []
        let longest = perChapter.map { $0.count }.max() ?? 0
        for index in 0..<longest {
            for list in perChapter where index < list.count {
                result.append(list[index])
            }
        }
        return result
    }

    /// The fish's held-out final questions.
    public static func finalExam(exam: Exam) -> [Question] {
        interleave(exam.concepts.map { exam.questions(in: .finalExam, concept: $0.id) })
    }

    static func leastAskedFirst(_ questions: [Question], stats: [String: QuestionStat]) -> [Question] {
        questions.enumerated()
            .sorted { a, b in
                let ta = stats[a.element.id]?.timesAsked ?? 0
                let tb = stats[b.element.id]?.timesAsked ?? 0
                return ta != tb ? ta < tb : a.offset < b.offset
            }
            .map { $0.element }
    }

    static func interleave(_ lists: [[Question]]) -> [Question] {
        var result: [Question] = []
        let longest = lists.map { $0.count }.max() ?? 0
        for index in 0..<longest {
            for list in lists where index < list.count {
                result.append(list[index])
            }
        }
        return result
    }

    static func unique(_ questions: [Question]) -> [Question] {
        var seen = Set<String>()
        return questions.filter { seen.insert($0.id).inserted }
    }
}
