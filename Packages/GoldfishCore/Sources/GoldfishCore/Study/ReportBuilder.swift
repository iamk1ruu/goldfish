import Foundation

public struct ReportFishLine: Codable, Equatable {
    public var concept: String
    public var question: String
    public var result: String
    public var sentence: String
}

public struct ReportStudentLine: Codable, Equatable {
    public var concept: String
    public var question: String
    public var chosen: String
    public var correctAnswer: String
    public var correct: Bool
    public var sure: String
}

/// What the cloud sees when writing a Report Card. It never includes the chapter text.
public struct ReportInput: Codable, Equatable {
    public var fishName: String
    public var chapterTitle: String
    public var concepts: [String]
    public var lesson: String
    public var fishResults: [ReportFishLine]
    public var studentResults: [ReportStudentLine]
}

/// Builds the report input, and the Report Card from the cloud's lists or a local draft.
public enum ReportBuilder {
    public static func input(
        fishName: String,
        chapter: Chapter,
        exam: Exam,
        lessonText: String,
        finalAnswers: [FishAnswer],
        studentAnswers: [StudentAnswer]
    ) -> ReportInput {
        func conceptName(_ questionID: String) -> String {
            guard let question = exam.question(questionID) else { return "" }
            return exam.concept(question.conceptID)?.name ?? ""
        }
        let fishLines = finalAnswers.map { answer in
            ReportFishLine(
                concept: conceptName(answer.questionID),
                question: exam.question(answer.questionID)?.stem ?? "",
                result: resultWord(answer.verdict),
                sentence: answer.traceSentence ?? ""
            )
        }
        let studentLines = studentAnswers.map { answer -> ReportStudentLine in
            let question = exam.question(answer.questionID)
            return ReportStudentLine(
                concept: conceptName(answer.questionID),
                question: question?.stem ?? "",
                chosen: question?.option(answer.chosenIndex) ?? "",
                correctAnswer: question?.correctOption ?? "",
                correct: answer.correct,
                sure: answer.sure.map { $0 ? "yes" : "no" } ?? "not said"
            )
        }
        return ReportInput(
            fishName: fishName,
            chapterTitle: chapter.title,
            concepts: exam.concepts.map { $0.name },
            lesson: lessonText,
            fishResults: fishLines,
            studentResults: studentLines
        )
    }

    /// The headline counts come from code. The lists come from the cloud, or from a local
    /// draft when the cloud report is still pending.
    public static func card(
        chapterID: String,
        draft: ReportDraft?,
        exam: Exam,
        finalAnswers: [FishAnswer],
        studentAnswers: [StudentAnswer],
        writtenBy: String,
        at date: Date
    ) -> ReportCard {
        let lists = draft ?? localDraft(exam: exam, finalAnswers: finalAnswers, studentAnswers: studentAnswers)
        return ReportCard(
            chapterID: chapterID,
            explainedWell: Array(lists.explainedWell.prefix(4)),
            misconceptions: Array(lists.misconceptions.prefix(4)),
            reviewNext: Array(lists.reviewNext.prefix(4)),
            coverageCorrect: finalAnswers.filter { $0.verdict == .correct }.count,
            coverageTotal: finalAnswers.count,
            unaidedCorrect: studentAnswers.filter { $0.correct }.count,
            unaidedTotal: studentAnswers.count,
            writtenBy: draft == nil ? "draft" : writtenBy,
            createdAt: date,
            isDraft: draft == nil
        )
    }

    /// A plain summary made on the phone, so the student sees something while offline.
    public static func localDraft(exam: Exam, finalAnswers: [FishAnswer], studentAnswers: [StudentAnswer]) -> ReportDraft {
        var explained: [String] = []
        var review: [String] = []
        var misconceptions: [String] = []

        for concept in exam.concepts {
            let fish = finalAnswers.filter { exam.question($0.questionID)?.conceptID == concept.id }
            let student = studentAnswers.filter { $0.conceptID == concept.id }
            let fishAllRight = !fish.isEmpty && fish.allSatisfy { $0.verdict == .correct }
            let studentMissed = student.contains { !$0.correct }
            if fishAllRight && !studentMissed {
                explained.append("\(concept.name): your explanation carried the fish through.")
            }
            if fish.contains(where: { $0.verdict == .gap }) {
                review.append("\(concept.name): your lesson did not cover everything the exam asked.")
            } else if studentMissed {
                review.append("\(concept.name): you missed a question on this without help.")
            }
        }
        for answer in finalAnswers where answer.verdict == .mixUp {
            if let sentence = answer.traceSentence, let question = exam.question(answer.questionID) {
                misconceptions.append("\"\(sentence)\" led to the wrong answer for: \(question.stem)")
            }
        }
        return ReportDraft(explainedWell: explained, misconceptions: misconceptions, reviewNext: review)
    }

    static func resultWord(_ verdict: FishVerdict) -> String {
        switch verdict {
        case .correct: return "correct"
        case .mixUp: return "mix-up (wrong answer from a lesson sentence)"
        case .gap: return "not taught"
        }
    }
}
