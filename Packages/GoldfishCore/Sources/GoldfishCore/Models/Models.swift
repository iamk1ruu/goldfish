import Foundation

// MARK: - Chapters and exams

/// Which part of the Hidden Exam a question belongs to.
public enum QuestionPool: String, Codable, CaseIterable {
    /// Asked to the fish in Pop Quizzes.
    case practice
    /// Held out for the fish's final exam.
    case finalExam = "final"
    /// Asked to the student only.
    case yourTurn

    /// Reads the pool name the cloud writes, tolerating spacing and case.
    public init?(cloudValue: String) {
        let cleaned = cloudValue.lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
        switch cleaned {
        case "practice": self = .practice
        case "final", "finalexam": self = .finalExam
        case "yourturn", "student": self = .yourTurn
        default: return nil
        }
    }
}

public struct Chapter: Codable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var sourceText: String
    public var createdAt: Date
    public var examDate: Date?
    public var isSample: Bool
    /// The deck this chapter belongs to. Nil only in data saved before decks existed;
    /// `GoldfishData.ensureDecks()` fills it in.
    public var deckID: String?
    /// The display name of the friend who shared this chapter. Nil for your own chapters.
    public var sharedBy: String?
    /// The code this chapter was opened from. Nil for your own chapters.
    public var shareCode: String?

    public init(
        id: String, title: String, sourceText: String, createdAt: Date, examDate: Date? = nil,
        isSample: Bool = false, deckID: String? = nil, sharedBy: String? = nil, shareCode: String? = nil
    ) {
        self.id = id
        self.title = title
        self.sourceText = sourceText
        self.createdAt = createdAt
        self.examDate = examDate
        self.isSample = isSample
        self.deckID = deckID
        self.sharedBy = sharedBy
        self.shareCode = shareCode
    }
}

public struct Concept: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var summary: String
    /// The question Curious Fish asks after a correct answer.
    public var whyQuestion: String

    public init(id: String, name: String, summary: String, whyQuestion: String) {
        self.id = id
        self.name = name
        self.summary = summary
        self.whyQuestion = whyQuestion
    }
}

public struct Question: Codable, Equatable, Identifiable {
    public var id: String
    public var conceptID: String
    public var stem: String
    public var options: [String]
    public var correctIndex: Int
    /// One per option. A quote must contain the chosen option's key term to earn credit.
    public var keyTerms: [String]
    public var explanation: String
    /// Copied from the chapter, so the question can be traced to its source.
    public var sourceQuote: String
    /// One sentence a student could write to teach the answer. Used by the fair exam check.
    public var modelSentence: String
    public var pool: QuestionPool
    /// The fair exam check result. Nil until the fair exam check has run.
    public var fairCheck: Bool?

    public init(
        id: String, conceptID: String, stem: String, options: [String], correctIndex: Int,
        keyTerms: [String], explanation: String, sourceQuote: String, modelSentence: String,
        pool: QuestionPool, fairCheck: Bool? = nil
    ) {
        self.id = id
        self.conceptID = conceptID
        self.stem = stem
        self.options = options
        self.correctIndex = correctIndex
        self.keyTerms = keyTerms
        self.explanation = explanation
        self.sourceQuote = sourceQuote
        self.modelSentence = modelSentence
        self.pool = pool
        self.fairCheck = fairCheck
    }

    public var correctOption: String {
        options.indices.contains(correctIndex) ? options[correctIndex] : ""
    }

    public func option(_ index: Int) -> String {
        options.indices.contains(index) ? options[index] : ""
    }
}

public struct Exam: Codable, Equatable {
    public var id: String
    public var chapterID: String
    public var concepts: [Concept]
    public var questions: [Question]
    public var compiledBy: String
    public var compiledAt: Date
    public var promptVersion: Int
    /// How many of the chapter's passages a question quotes. Nil for exams written before the check.
    public var coverage: ExamCoverage?

    public init(
        id: String, chapterID: String, concepts: [Concept], questions: [Question],
        compiledBy: String, compiledAt: Date, promptVersion: Int, coverage: ExamCoverage? = nil
    ) {
        self.id = id
        self.chapterID = chapterID
        self.concepts = concepts
        self.questions = questions
        self.compiledBy = compiledBy
        self.compiledAt = compiledAt
        self.promptVersion = promptVersion
        self.coverage = coverage
    }

    public func concept(_ id: String) -> Concept? {
        concepts.first { $0.id == id }
    }

    public func question(_ id: String) -> Question? {
        questions.first { $0.id == id }
    }

    public func questions(in pool: QuestionPool, concept conceptID: String? = nil) -> [Question] {
        questions.filter { $0.pool == pool && (conceptID == nil || $0.conceptID == conceptID) }
    }

    public func conceptIndex(_ id: String) -> Int {
        concepts.firstIndex { $0.id == id } ?? concepts.count
    }
}

// MARK: - Lessons and quizzes

public enum LessonKind: String, Codable {
    /// The first time the student teaches the chapter.
    case first
    /// A later session where the fish has forgotten and the old lesson is hidden.
    case freshWater
}

public struct Lesson: Codable, Equatable, Identifiable {
    public var id: String
    public var chapterID: String
    public var kind: LessonKind
    /// Concept ID to the student's text for that concept.
    public var sections: [String: String]
    public var peekCount: Int
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String, chapterID: String, kind: LessonKind, sections: [String: String] = [:],
        peekCount: Int = 0, createdAt: Date, updatedAt: Date? = nil
    ) {
        self.id = id
        self.chapterID = chapterID
        self.kind = kind
        self.sections = sections
        self.peekCount = peekCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }

    /// Fresh Water lessons are written with the previous lesson hidden.
    public var writtenFromMemory: Bool {
        kind == .freshWater
    }

    public func section(_ conceptID: String) -> String {
        sections[conceptID] ?? ""
    }
}

public struct FishAnswer: Codable, Equatable {
    public var questionID: String
    public var choice: FishChoice
    public var quote: String
    public var verdict: FishVerdict
    /// The lesson sentence the quote came from, for highlighting in Miss review.
    public var traceSentence: String?
    public var tier: FishTier
    public var modelVersion: String
    public var latencyMs: Int
    public var raw: String
    public var note: String?
    /// True when the answer came from the cache instead of a model.
    public var cached: Bool

    public init(
        questionID: String, choice: FishChoice, quote: String, verdict: FishVerdict,
        traceSentence: String?, tier: FishTier, modelVersion: String, latencyMs: Int,
        raw: String, note: String? = nil, cached: Bool = false
    ) {
        self.questionID = questionID
        self.choice = choice
        self.quote = quote
        self.verdict = verdict
        self.traceSentence = traceSentence
        self.tier = tier
        self.modelVersion = modelVersion
        self.latencyMs = latencyMs
        self.raw = raw
        self.note = note
        self.cached = cached
    }
}

public enum QuizKind: String, Codable {
    /// A Pop Quiz on practice questions.
    case pop
    /// Only the questions missed last time.
    case recheck
    /// The fish's held-out final exam.
    case finalExam = "final"
    /// Every practice question, for a teach-off with a friend. Recorded like a Pop Quiz.
    case teachOff
}

public struct QuizRun: Codable, Equatable, Identifiable {
    public var id: String
    public var chapterID: String
    public var lessonID: String
    public var kind: QuizKind
    public var lessonHash: String
    public var answers: [FishAnswer]
    /// The student's guess at the fish's score.
    public var predictedScore: Int?
    public var startedAt: Date
    public var finishedAt: Date?

    public init(
        id: String, chapterID: String, lessonID: String, kind: QuizKind, lessonHash: String,
        answers: [FishAnswer] = [], predictedScore: Int? = nil, startedAt: Date, finishedAt: Date? = nil
    ) {
        self.id = id
        self.chapterID = chapterID
        self.lessonID = lessonID
        self.kind = kind
        self.lessonHash = lessonHash
        self.answers = answers
        self.predictedScore = predictedScore
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }

    public var score: Int {
        answers.filter { $0.verdict == .correct }.count
    }

    public var misses: [FishAnswer] {
        answers.filter { $0.verdict != .correct }
    }

    public func count(on tier: FishTier) -> Int {
        answers.filter { $0.tier == tier && !$0.cached }.count
    }
}

public enum ShortAnswerGrade: String, Codable, Equatable {
    case match
    case partial
    case miss
}

/// The result of the last Grading Check on this phone.
public struct GradingCheckRecord: Codable, Equatable {
    public var passed: Bool
    public var agreed: Int
    public var total: Int
    public var harmful: Int
    public var modelVersion: String
    public var ranAt: Date

    public init(passed: Bool, agreed: Int, total: Int, harmful: Int, modelVersion: String, ranAt: Date) {
        self.passed = passed
        self.agreed = agreed
        self.total = total
        self.harmful = harmful
        self.modelVersion = modelVersion
        self.ranAt = ranAt
    }

    public init(_ result: GradingCheck.Result, at date: Date) {
        self.init(
            passed: result.passed, agreed: result.agreed, total: result.trials.count,
            harmful: result.harmful, modelVersion: result.modelVersion, ranAt: date
        )
    }
}

/// One unaided answer from the student.
public struct StudentAnswer: Codable, Equatable {
    public var questionID: String
    public var conceptID: String
    /// What the student typed from memory before seeing the options.
    public var recallText: String
    public var chosenIndex: Int
    /// Nil when the student did not say.
    public var sure: Bool?
    public var correct: Bool
    public var answeredAt: Date
    public var day: Day
    public var isFinal: Bool
    public var recallGrade: ShortAnswerGrade?

    public init(
        questionID: String, conceptID: String, recallText: String, chosenIndex: Int, sure: Bool?,
        correct: Bool, answeredAt: Date, day: Day, isFinal: Bool = false, recallGrade: ShortAnswerGrade? = nil
    ) {
        self.questionID = questionID
        self.conceptID = conceptID
        self.recallText = recallText
        self.chosenIndex = chosenIndex
        self.sure = sure
        self.correct = correct
        self.answeredAt = answeredAt
        self.day = day
        self.isFinal = isFinal
        self.recallGrade = recallGrade
    }

    public var sureButWrong: Bool {
        sure == true && !correct
    }
}

// MARK: - Progress

/// What the fish has shown it learned for a concept.
public enum FishLevel: Int, Codable, Comparable {
    case notTaught = 0
    case taught = 1
    case recalled = 2

    public static func < (lhs: FishLevel, rhs: FishLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// The Mastery Map states.
public enum ConceptState: String, Codable, CaseIterable {
    case notTaught
    case taught
    case recalled
    case mastered

    public var label: String {
        switch self {
        case .notTaught: return "Not taught"
        case .taught: return "Taught"
        case .recalled: return "Recalled"
        case .mastered: return "Mastered"
        }
    }
}

public struct ConceptProgress: Codable, Equatable {
    public var conceptID: String
    public var fishLevel: FishLevel
    /// Your Turn box, 0 to 3.
    public var box: Int
    public var dueOn: Day?
    public var lastBoxChangeOn: Day?
    /// Days with a correct unaided answer since the last miss.
    public var correctDays: [Day]
    /// Set when a mastered concept is missed. It shows as Recalled until mastered again.
    public var slipped: Bool
    /// "Sure but wrong" questions, shown first next time.
    public var retryQuestionIDs: [String]

    public init(
        conceptID: String, fishLevel: FishLevel = .notTaught, box: Int = 0, dueOn: Day? = nil,
        lastBoxChangeOn: Day? = nil, correctDays: [Day] = [], slipped: Bool = false, retryQuestionIDs: [String] = []
    ) {
        self.conceptID = conceptID
        self.fishLevel = fishLevel
        self.box = box
        self.dueOn = dueOn
        self.lastBoxChangeOn = lastBoxChangeOn
        self.correctDays = correctDays
        self.slipped = slipped
        self.retryQuestionIDs = retryQuestionIDs
    }
}

public struct ChapterProgress: Codable, Equatable {
    public var chapterID: String
    public var firstTaughtOn: Day?
    public var lastSessionOn: Day?
    public var lastFreshWaterOn: Day?
    public var freshWaterDone: Int
    public var nextDueOn: Day?

    public init(
        chapterID: String, firstTaughtOn: Day? = nil, lastSessionOn: Day? = nil,
        lastFreshWaterOn: Day? = nil, freshWaterDone: Int = 0, nextDueOn: Day? = nil
    ) {
        self.chapterID = chapterID
        self.firstTaughtOn = firstTaughtOn
        self.lastSessionOn = lastSessionOn
        self.lastFreshWaterOn = lastFreshWaterOn
        self.freshWaterDone = freshWaterDone
        self.nextDueOn = nextDueOn
    }
}

/// How the fish has done on one question across all quizzes.
public struct QuestionStat: Codable, Equatable {
    public var timesAsked: Int
    public var timesMissed: Int
    public var lastVerdict: FishVerdict?

    public init(timesAsked: Int = 0, timesMissed: Int = 0, lastVerdict: FishVerdict? = nil) {
        self.timesAsked = timesAsked
        self.timesMissed = timesMissed
        self.lastVerdict = lastVerdict
    }

    /// The correct answer is shown only after the same question is missed twice.
    public var revealsAnswer: Bool {
        timesMissed >= 2
    }
}

/// "When I ___, I'll teach Finn."
public struct ReminderPlan: Codable, Equatable {
    public var cue: String
    public var hour: Int
    public var minute: Int
    public var enabled: Bool

    public init(cue: String, hour: Int, minute: Int, enabled: Bool) {
        self.cue = cue
        self.hour = hour
        self.minute = minute
        self.enabled = enabled
    }
}

/// The summary after a final exam.
public struct ReportCard: Codable, Equatable {
    public var chapterID: String
    public var explainedWell: [String]
    public var misconceptions: [String]
    public var reviewNext: [String]
    /// "Your explanation covered X of Y": final questions the fish got right.
    public var coverageCorrect: Int
    public var coverageTotal: Int
    /// "You answered X of Y unaided."
    public var unaidedCorrect: Int
    public var unaidedTotal: Int
    public var writtenBy: String
    public var createdAt: Date
    /// True for the on-phone draft shown while the cloud report is pending.
    public var isDraft: Bool

    public init(
        chapterID: String, explainedWell: [String], misconceptions: [String], reviewNext: [String],
        coverageCorrect: Int, coverageTotal: Int, unaidedCorrect: Int, unaidedTotal: Int,
        writtenBy: String, createdAt: Date, isDraft: Bool
    ) {
        self.chapterID = chapterID
        self.explainedWell = explainedWell
        self.misconceptions = misconceptions
        self.reviewNext = reviewNext
        self.coverageCorrect = coverageCorrect
        self.coverageTotal = coverageTotal
        self.unaidedCorrect = unaidedCorrect
        self.unaidedTotal = unaidedTotal
        self.writtenBy = writtenBy
        self.createdAt = createdAt
        self.isDraft = isDraft
    }
}
