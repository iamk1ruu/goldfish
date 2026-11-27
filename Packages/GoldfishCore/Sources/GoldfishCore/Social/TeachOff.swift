import Foundation

/// How one Finn did in a teach-off: which questions his lesson got him through, and where he answered.
/// Only verdicts are kept. The lesson itself never leaves the phone.
public struct TeachOffScore: Codable, Equatable {
    /// Question ID to whether the fish got it right.
    public var results: [String: Bool]
    public var onDevice: Int
    public var cloud: Int
    public var finishedAt: Date

    public init(results: [String: Bool], onDevice: Int, cloud: Int, finishedAt: Date) {
        self.results = results
        self.onDevice = onDevice
        self.cloud = cloud
        self.finishedAt = finishedAt
    }

    public var right: Int {
        results.values.filter { $0 }.count
    }

    public var total: Int {
        results.count
    }
}

/// One concept in a teach-off, for both lessons, on the questions both Finns answered.
public struct TeachOffConcept: Equatable, Identifiable {
    public let id: String
    public let name: String
    public let mine: Int
    public let theirs: Int
    public let total: Int
}

/// Both sides of a finished teach-off.
public struct TeachOffComparison: Equatable {
    public let mine: Int
    public let theirs: Int
    /// Questions both Finns answered. Usually every practice question.
    public let total: Int
    public let concepts: [TeachOffConcept]

    /// Concepts where your lesson got Finn further.
    public var yoursClearer: [TeachOffConcept] {
        concepts.filter { $0.mine > $0.theirs }
    }

    /// Concepts where your friend's lesson got their Finn further.
    public var theirsClearer: [TeachOffConcept] {
        concepts.filter { $0.theirs > $0.mine }
    }
}

/// The teach-off. Two students teach the same shared chapter to their own Finn, and each Finn takes
/// every practice question from his student's lesson. What is compared is whose explanation worked,
/// not who is faster or who remembers more. There is no ranking beyond the two of you.
public enum TeachOff {
    /// Every practice question, concept by concept. Both students have had the same chance to see them
    /// in Pop Quizzes, so neither side has an advantage, and fixing a missed one is the point of the app.
    public static func questions(exam: Exam) -> [Question] {
        exam.questions(in: .practice).sorted {
            let a = exam.conceptIndex($0.conceptID)
            let b = exam.conceptIndex($1.conceptID)
            return a != b ? a < b : $0.id < $1.id
        }
    }

    public static func score(answers: [FishAnswer], at date: Date) -> TeachOffScore {
        var results: [String: Bool] = [:]
        for answer in answers {
            results[answer.questionID] = answer.verdict == .correct
        }
        return TeachOffScore(
            results: results,
            onDevice: answers.filter { $0.tier == .onDevice }.count,
            cloud: answers.filter { $0.tier == .cloud }.count,
            finishedAt: date
        )
    }

    /// Compares on the questions both Finns answered, so an exam that changed on one phone after
    /// sharing (the fair exam check can drop questions) still compares like with like.
    public static func compare(mine: TeachOffScore, theirs: TeachOffScore, exam: Exam) -> TeachOffComparison {
        let common = Set(mine.results.keys).intersection(theirs.results.keys)
            .filter { exam.question($0) != nil }
        var concepts: [TeachOffConcept] = []
        for concept in exam.concepts {
            let ids = common.filter { exam.question($0)?.conceptID == concept.id }
            guard !ids.isEmpty else { continue }
            concepts.append(TeachOffConcept(
                id: concept.id,
                name: concept.name,
                mine: ids.filter { mine.results[$0] == true }.count,
                theirs: ids.filter { theirs.results[$0] == true }.count,
                total: ids.count
            ))
        }
        return TeachOffComparison(
            mine: common.filter { mine.results[$0] == true }.count,
            theirs: common.filter { theirs.results[$0] == true }.count,
            total: common.count,
            concepts: concepts
        )
    }

    /// What Finn says about the result. Kind either way: a lower score is something to teach better.
    public static func finnLine(_ comparison: TeachOffComparison, fishName: String, friendName: String) -> String {
        let clearer = comparison.theirsClearer.map { $0.name }
        if comparison.mine > comparison.theirs {
            if let first = clearer.first {
                return "Your lesson got me further. \(friendName) explained \(first) better, though. Ask them how they put it."
            }
            return "Your lesson got me further on every idea. Explain it the same way next time, from memory."
        }
        if comparison.mine < comparison.theirs {
            if let first = clearer.first {
                return "\(friendName)'s lesson was clearer on \(first). Fix that section and I'll take the questions again."
            }
            return "\(friendName)'s lesson got their fish further. Fix the sections I missed and run it again."
        }
        if clearer.isEmpty && comparison.yoursClearer.isEmpty {
            return "Your lessons taught us exactly the same. Nice teaching, both of you."
        }
        return "A tie overall, but you each explained different ideas better. Swap tips."
    }
}
