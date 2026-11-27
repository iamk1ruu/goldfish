import Foundation

public struct DroppedQuestion: Equatable {
    public let concept: String
    public let stem: String
    public let reasons: [String]
}

public struct ExamBuildResult {
    public let exam: Exam
    public let dropped: [DroppedQuestion]

    public var kept: Int {
        exam.questions.count
    }

    /// Fewer than the minimum survived, so the compile should be retried once.
    public var needsRetry: Bool {
        kept < ExamValidator.minimumQuestions || exam.questions(in: .practice).isEmpty
    }
}

/// Checks the cloud's exam in code before anything is stored.
public enum ExamValidator {
    public static let minimumQuestions = 12
    public static let minimumKeyTermLength = 3

    /// Everything wrong with one question. Empty means it passes.
    public static func problems(_ q: QuestionDraft, chapter: WordText) -> [String] {
        var problems: [String] = []
        if TextNormalizer.normalize(q.stem).isEmpty {
            problems.append("empty question")
        }
        if QuestionPool(cloudValue: q.pool) == nil {
            problems.append("unknown pool \"\(q.pool)\"")
        }

        let options = q.options.map { TextNormalizer.normalize($0) }
        if options.count != 4 {
            problems.append("needs exactly 4 options")
        }
        if options.contains("") || Set(options).count != options.count {
            problems.append("options must be distinct and non-empty")
        }
        let keyValid = options.indices.contains(q.correctIndex)
        if !keyValid {
            problems.append("answer key out of range")
        }

        let keys = q.keyTerms.map { TextNormalizer.normalize($0) }
        if keys.count != options.count {
            problems.append("needs one key term per option")
        } else {
            if Set(keys).count != keys.count {
                problems.append("key terms must be distinct")
            }
            for (index, key) in keys.enumerated() {
                if key.count < minimumKeyTermLength {
                    problems.append("key term \(index + 1) is too short")
                    continue
                }
                if !options[index].contains(key) {
                    problems.append("key term \(index + 1) is not in its option")
                }
                for (other, text) in options.enumerated() where other != index && text.contains(key) {
                    problems.append("key term \(index + 1) also appears in option \(other + 1)")
                }
            }
            if keyValid {
                let sentence = TextNormalizer.normalize(q.modelSentence)
                if !sentence.contains(keys[q.correctIndex]) {
                    problems.append("teaching sentence lacks the answer's key term")
                }
                for (index, key) in keys.enumerated() where index != q.correctIndex && !key.isEmpty && sentence.contains(key) {
                    problems.append("teaching sentence mentions wrong option \(index + 1)")
                }
            }
        }

        if TextTools.words(q.sourceQuote).count < 3 || !chapter.contains(q.sourceQuote) {
            problems.append("source quote not found in the chapter")
        }
        return problems
    }

    /// Validates a draft and turns it into a stored exam with IDs and balanced answer letters.
    public static func build(
        draft: ExamDraft,
        chapterID: String,
        chapterText: String,
        compiledBy: String,
        compiledAt: Date,
        promptVersion: Int = CloudPrompts.examVersion
    ) -> ExamBuildResult {
        let chapter = WordText(chapterText)
        var concepts: [Concept] = []
        var questions: [Question] = []
        var dropped: [DroppedQuestion] = []

        for conceptDraft in draft.concepts {
            let name = conceptDraft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let conceptID = "\(chapterID).c\(concepts.count + 1)"
            var kept: [Question] = []
            var counters: [QuestionPool: Int] = [:]

            for questionDraft in conceptDraft.questions {
                let issues = problems(questionDraft, chapter: chapter)
                guard issues.isEmpty, let pool = QuestionPool(cloudValue: questionDraft.pool) else {
                    dropped.append(DroppedQuestion(concept: name, stem: questionDraft.stem, reasons: issues))
                    continue
                }
                let number = (counters[pool] ?? 0) + 1
                counters[pool] = number
                kept.append(Question(
                    id: "\(conceptID).\(poolLetter(pool))\(number)",
                    conceptID: conceptID,
                    stem: questionDraft.stem.trimmingCharacters(in: .whitespacesAndNewlines),
                    options: questionDraft.options.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) },
                    correctIndex: questionDraft.correctIndex,
                    keyTerms: questionDraft.keyTerms.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) },
                    explanation: questionDraft.explanation,
                    sourceQuote: questionDraft.sourceQuote,
                    modelSentence: questionDraft.modelSentence,
                    pool: pool
                ))
            }

            guard !kept.isEmpty else { continue }
            concepts.append(Concept(
                id: conceptID,
                name: name,
                summary: conceptDraft.summary,
                whyQuestion: conceptDraft.whyQuestion
            ))
            questions.append(contentsOf: kept)
        }

        let balanced = balanceLetters(questions, seed: StableHash.value(chapterID))
        let exam = Exam(
            id: "\(chapterID).exam",
            chapterID: chapterID,
            concepts: concepts,
            questions: balanced,
            compiledBy: compiledBy,
            compiledAt: compiledAt,
            promptVersion: promptVersion
        )
        return ExamBuildResult(exam: exam, dropped: dropped)
    }

    static func poolLetter(_ pool: QuestionPool) -> String {
        switch pool {
        case .practice: return "p"
        case .finalExam: return "f"
        case .yourTurn: return "y"
        }
    }

    /// Spreads correct answers evenly across A to D, in a fixed shuffled order.
    public static func balanceLetters(_ questions: [Question], seed: UInt64) -> [Question] {
        var order = Array(questions.indices)
        var generator = SeededGenerator(seed: seed)
        order.shuffle(using: &generator)
        var result = questions
        for (rank, index) in order.enumerated() {
            result[index] = moveCorrect(questions[index], to: rank % 4)
        }
        return result
    }

    static func moveCorrect(_ question: Question, to target: Int) -> Question {
        guard question.options.count == 4, question.keyTerms.count == 4,
              (0..<4).contains(target), (0..<4).contains(question.correctIndex),
              question.correctIndex != target
        else { return question }
        var order = Array(0..<4).filter { $0 != question.correctIndex }
        order.insert(question.correctIndex, at: target)
        var moved = question
        moved.options = order.map { question.options[$0] }
        moved.keyTerms = order.map { question.keyTerms[$0] }
        moved.correctIndex = target
        return moved
    }
}
