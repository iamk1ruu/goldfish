import Foundation

/// Everything the app stores, saved as one JSON file.
///
/// Decoding tolerates missing keys, so a build that adds a field can still read
/// the file an older build wrote. Sideloaded builds are reinstalled often.
public struct GoldfishData: Codable, Equatable {
    /// 2 added decks. Version 1 files are read as they are and given a deck by `ensureDecks()`.
    public static let currentVersion = 2

    public var version: Int
    public var fishName: String
    public var onboarded: Bool
    /// Subjects, in the order the student made them.
    public var decks: [Deck]
    /// The deck Today, the Decks tab and Orla follow.
    public var currentDeckID: String?
    public var chapters: [Chapter]
    /// By chapter ID.
    public var exams: [String: Exam]
    public var lessons: [Lesson]
    public var quizRuns: [QuizRun]
    public var studentAnswers: [StudentAnswer]
    /// By concept ID. Concept IDs include the chapter ID, so they are unique.
    public var concepts: [String: ConceptProgress]
    /// By chapter ID.
    public var chapterProgress: [String: ChapterProgress]
    /// By question ID.
    public var questionStats: [String: QuestionStat]
    /// By `AnswerCacheKey`. Unchanged lessons are never re-asked.
    public var answerCache: [String: FishAnswer]
    /// By chapter ID.
    public var reports: [String: ReportCard]
    /// Chapter IDs whose cloud report is waiting for a connection.
    public var pendingReports: [String]
    public var reminder: ReminderPlan?
    /// The day Curious Fish last asked, by chapter ID.
    public var curiousAsked: [String: Day]
    /// Days with at least one finished Pop Quiz.
    public var teachingDays: [Day]
    /// Sounds and haptics.
    public var preferences: Preferences
    /// The profile, once the student turns friends on. Nil means friends are off.
    public var social: SocialState?
    /// Share codes for chapters this student shared, by chapter ID, so sharing again reuses the code.
    public var sharedCodes: [String: String]
    /// The last Grading Check run on this phone. Graded recall goes on when it passed.
    public var gradingCheck: GradingCheckRecord?

    public init() {
        version = GoldfishData.currentVersion
        fishName = "Finn"
        onboarded = false
        decks = []
        currentDeckID = nil
        chapters = []
        exams = [:]
        lessons = []
        quizRuns = []
        studentAnswers = []
        concepts = [:]
        chapterProgress = [:]
        questionStats = [:]
        answerCache = [:]
        reports = [:]
        pendingReports = []
        reminder = nil
        curiousAsked = [:]
        teachingDays = []
        preferences = Preferences()
        social = nil
        sharedCodes = [:]
        gradingCheck = nil
    }

    enum CodingKeys: String, CodingKey {
        case version, fishName, onboarded, decks, currentDeckID, chapters, exams, lessons, quizRuns, studentAnswers
        case concepts, chapterProgress, questionStats, answerCache, reports, pendingReports
        case reminder, curiousAsked, teachingDays, preferences, social, sharedCodes, gradingCheck
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let empty = GoldfishData()
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? empty.version
        fishName = try c.decodeIfPresent(String.self, forKey: .fishName) ?? empty.fishName
        onboarded = try c.decodeIfPresent(Bool.self, forKey: .onboarded) ?? empty.onboarded
        decks = try c.decodeIfPresent([Deck].self, forKey: .decks) ?? []
        currentDeckID = try c.decodeIfPresent(String.self, forKey: .currentDeckID)
        chapters = try c.decodeIfPresent([Chapter].self, forKey: .chapters) ?? []
        exams = try c.decodeIfPresent([String: Exam].self, forKey: .exams) ?? [:]
        lessons = try c.decodeIfPresent([Lesson].self, forKey: .lessons) ?? []
        quizRuns = try c.decodeIfPresent([QuizRun].self, forKey: .quizRuns) ?? []
        studentAnswers = try c.decodeIfPresent([StudentAnswer].self, forKey: .studentAnswers) ?? []
        concepts = try c.decodeIfPresent([String: ConceptProgress].self, forKey: .concepts) ?? [:]
        chapterProgress = try c.decodeIfPresent([String: ChapterProgress].self, forKey: .chapterProgress) ?? [:]
        questionStats = try c.decodeIfPresent([String: QuestionStat].self, forKey: .questionStats) ?? [:]
        answerCache = try c.decodeIfPresent([String: FishAnswer].self, forKey: .answerCache) ?? [:]
        reports = try c.decodeIfPresent([String: ReportCard].self, forKey: .reports) ?? [:]
        pendingReports = try c.decodeIfPresent([String].self, forKey: .pendingReports) ?? []
        reminder = try c.decodeIfPresent(ReminderPlan.self, forKey: .reminder)
        curiousAsked = try c.decodeIfPresent([String: Day].self, forKey: .curiousAsked) ?? [:]
        teachingDays = try c.decodeIfPresent([Day].self, forKey: .teachingDays) ?? []
        preferences = try c.decodeIfPresent(Preferences.self, forKey: .preferences) ?? Preferences()
        social = try c.decodeIfPresent(SocialState.self, forKey: .social)
        sharedCodes = try c.decodeIfPresent([String: String].self, forKey: .sharedCodes) ?? [:]
        gradingCheck = try c.decodeIfPresent(GradingCheckRecord.self, forKey: .gradingCheck)
        // Files from before decks get one, so every chapter has a home.
        ensureDecks()
    }

    // MARK: Lookups

    public func chapter(_ id: String) -> Chapter? {
        chapters.first { $0.id == id }
    }

    /// The newest lesson for a chapter.
    public func currentLesson(for chapterID: String) -> Lesson? {
        lessons.filter { $0.chapterID == chapterID }.max { $0.createdAt < $1.createdAt }
    }

    /// The lesson before the current one, for "Compare with last time".
    public func previousLesson(for chapterID: String) -> Lesson? {
        let sorted = lessons.filter { $0.chapterID == chapterID }.sorted { $0.createdAt < $1.createdAt }
        return sorted.count >= 2 ? sorted[sorted.count - 2] : nil
    }

    /// A teach-off counts, so Miss review can fix what Finn missed in one.
    public func latestRun(for chapterID: String, kinds: Set<QuizKind> = [.pop, .recheck, .teachOff]) -> QuizRun? {
        quizRuns.filter { $0.chapterID == chapterID && kinds.contains($0.kind) && $0.finishedAt != nil }
            .max { $0.startedAt < $1.startedAt }
    }

    public func conceptState(_ conceptID: String) -> ConceptState {
        MasteryRules.state(concepts[conceptID])
    }
}
