import Foundation

/// The four lessons each Fish Check question is tried with.
public enum FidelityCondition: String, CaseIterable {
    /// Every fact is taught correctly.
    case good
    /// The fact for this question is missing, the rest are present.
    case gap
    /// The fact for this question is taught wrongly.
    case wrong
    /// Nothing is taught.
    case empty
}

/// What the fish did on one trial.
public enum FidelityPick: String {
    case correct
    case planted
    case other
    case abstain
    case invalid
    case error
}

public struct FidelityTrial {
    public let itemID: String
    public let condition: FidelityCondition
    public let run: Int
    public let latencyMs: Int
    public let raw: String?
    public let error: String?
    public let pick: FidelityPick
    public let quote: String
    /// The quote is a real span of the lesson.
    public let verbatim: Bool
    /// The quote mentions the key term of the chosen option.
    public let keyed: Bool
    /// The trial matched what a faithful fish would do.
    public let asExpected: Bool
    public let tier: FishTier?
}

public struct FidelityStats: Equatable {
    public var total = 0
    public var errors = 0
    public var valid = 0
    public var correct = 0
    public var planted = 0
    public var other = 0
    public var abstain = 0
    public var answered = 0
    public var verbatim = 0
    public var creditedQuote = 0
    public var creditedFull = 0
    public var followed = 0

    public init() {}
}

public struct FidelityRates: Equatable {
    /// Good lesson: picked the correct option.
    public var learnsRaw = 0.0
    /// Good lesson: correct, with a quote that passes both checks.
    public var learnsCredited = 0.0
    /// Wrong lesson: picked the planted option.
    public var misledRaw = 0.0
    /// Wrong lesson: planted, with a quote that passes both checks.
    public var misledCredited = 0.0
    /// Wrong lesson: picked the truly correct option anyway.
    public var overridesLesson = 0.0
    /// Missing fact: picked the correct option anyway.
    public var leakRaw = 0.0
    /// Missing fact: correct, and the quote was a real sentence.
    public var leakQuoteOnly = 0.0
    /// Missing fact: correct, and the quote passed both checks.
    public var leakFull = 0.0
    public var gapAbstains = 0.0
    public var emptyAbstains = 0.0
    public var emptyLeakRaw = 0.0

    public init() {}
}

/// Go or no-go lines. These are judgment calls, set before seeing real results.
public struct FidelityThresholds: Equatable {
    /// A good lesson must earn credit at least this often.
    public var learns = 0.8
    /// A wrong lesson must mislead the fish at least this often.
    public var misled = 0.7
    /// A missing fact must earn credit no more than this often.
    public var leak = 0.1
    /// Valid trials needed per condition to reach a verdict.
    public var minValid = 15
    public var maxErrorRate = 0.1

    public init() {}
}

public enum FidelityVerdictCode: String {
    case go = "GO"
    case goWithKeywordCheck = "GO_WITH_KEYWORD_CHECK"
    case needsPromptWork = "NEEDS_PROMPT_WORK"
    case noGo = "NO_GO"
    case inconclusive = "INCONCLUSIVE"
}

public struct FidelityVerdict: Equatable {
    public let code: FidelityVerdictCode
    public let title: String
    public let detail: String
}

public struct FidelitySummary {
    public let stats: [FidelityCondition: FidelityStats]
    public let rates: FidelityRates
    public let totalErrors: Int
    public let errorRate: Double
    /// Share of repeated questions where the fish made the same choice every time.
    public let consistency: Double?
    public let latencyP50: Int
    public let latencyP90: Int
    public let latencyMean: Int
    public let tierCounts: [FishTier: Int]
    public let verdict: FidelityVerdict
}

public struct FidelityResult {
    public let trials: [FidelityTrial]
    public let planned: Int
    public let stoppedReason: String?
    public let summary: FidelitySummary
}

/// Context printed at the top of a Fish Check report.
public struct FidelityMeta {
    public var source: String
    public var device: String
    public var repeats: Int
    public var date: Date

    public init(source: String, device: String, repeats: Int, date: Date = Date()) {
        self.source = source
        self.device = device
        self.repeats = repeats
        self.date = date
    }
}
