import Foundation

/// Asks the on-device fish each question with only its model teaching sentence as the lesson.
/// A question the fish cannot answer even from an ideal sentence is unfair to the student.
public enum FairExamCheck {
    public static func run(
        questions: [Question],
        asker: FishAsker,
        shouldStop: () -> Bool = { false },
        onProgress: (_ done: Int, _ total: Int) -> Void = { _, _ in }
    ) async -> [String: Bool] {
        var results: [String: Bool] = [:]
        for (index, question) in questions.enumerated() {
            if shouldStop() {
                break
            }
            if let answer = try? await asker.ask(question, lesson: question.modelSentence) {
                results[question.id] = answer.verdict == .correct
            }
            onProgress(index + 1, questions.count)
        }
        return results
    }

    /// Records results and drops failures, but never removes a concept's last question in a pool.
    public static func apply(_ results: [String: Bool], to exam: Exam) -> (exam: Exam, dropped: [String]) {
        var updated = exam
        for index in updated.questions.indices {
            if let passed = results[updated.questions[index].id] {
                updated.questions[index].fairCheck = passed
            }
        }
        var kept: [Question] = []
        var dropped: [String] = []
        for question in updated.questions {
            if question.fairCheck == false {
                let others = updated.questions.filter {
                    $0.id != question.id && $0.conceptID == question.conceptID
                        && $0.pool == question.pool && $0.fairCheck != false
                }
                if !others.isEmpty {
                    dropped.append(question.id)
                    continue
                }
            }
            kept.append(question)
        }
        updated.questions = kept
        return (updated, dropped)
    }
}
