import Foundation

/// Values that Remote Config can change without a new build.
/// Every value has a built-in default, so the app works offline and before the first fetch.
public struct GoldfishSettings: Equatable {
    public var examModel = "gemini-3.8-flash"
    public var reportModel = "gemini-3.8-flash"
    public var fishCloudModel = "gemini-3.5-flash-lite"
    public var bowlWordLimit = 600
    public var popQuizLength = 8
    public var yourTurnLength = 5
    public var finalYourTurnLength = 10
    public var quoteMinWords = 3
    public var quoteMaxWords = 30
    public var promptVersion = 1
    public var chapterWordLimit = 15_000
    /// Graded recall stays off until on-device grading proves reliable. A passed Grading Check on the phone
    /// also turns it on, for that phone.
    public var shortAnswerGrading = false
    /// The cosine similarity a sentence needs to count as meaning the same as Orla's question.
    /// A starting value, not yet measured on the iPhone.
    public var tutorMeaningFloor = PassageIndex.defaultMeaningFloor

    public init() {}

    public var quoteRules: QuoteRules {
        QuoteRules(minWords: quoteMinWords, maxWords: quoteMaxWords)
    }

    /// Remote Config keys, in the order Diagnostics shows them.
    public static let remoteKeys = [
        "exam_model", "report_model", "fish_cloud_model", "bowl_word_limit", "pop_quiz_length",
        "your_turn_length", "final_your_turn_length", "quote_min_words", "quote_max_words",
        "prompt_version", "chapter_word_limit", "short_answer_grading", "tutor_meaning_floor",
    ]

    /// Applies one remote value. Values that do not parse, or are out of range, are ignored.
    public mutating func apply(_ raw: String, forKey key: String) {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        func int(_ range: ClosedRange<Int>) -> Int? {
            guard let number = Int(value), range.contains(number) else { return nil }
            return number
        }
        switch key {
        case "exam_model": examModel = value
        case "report_model": reportModel = value
        case "fish_cloud_model": fishCloudModel = value
        case "bowl_word_limit": if let n = int(100...2000) { bowlWordLimit = n }
        case "pop_quiz_length": if let n = int(1...20) { popQuizLength = n }
        case "your_turn_length": if let n = int(1...20) { yourTurnLength = n }
        case "final_your_turn_length": if let n = int(1...40) { finalYourTurnLength = n }
        case "quote_min_words": if let n = int(1...10) { quoteMinWords = n }
        case "quote_max_words": if let n = int(5...80) { quoteMaxWords = n }
        case "prompt_version": if let n = int(1...999) { promptVersion = n }
        case "chapter_word_limit": if let n = int(1000...60_000) { chapterWordLimit = n }
        case "short_answer_grading":
            let lowered = value.lowercased()
            if ["true", "1", "yes"].contains(lowered) { shortAnswerGrading = true }
            if ["false", "0", "no"].contains(lowered) { shortAnswerGrading = false }
        case "tutor_meaning_floor":
            if let number = Double(value), (0.0...1.0).contains(number) { tutorMeaningFloor = number }
        default: break
        }
    }

    public func value(forKey key: String) -> String {
        switch key {
        case "exam_model": return examModel
        case "report_model": return reportModel
        case "fish_cloud_model": return fishCloudModel
        case "bowl_word_limit": return String(bowlWordLimit)
        case "pop_quiz_length": return String(popQuizLength)
        case "your_turn_length": return String(yourTurnLength)
        case "final_your_turn_length": return String(finalYourTurnLength)
        case "quote_min_words": return String(quoteMinWords)
        case "quote_max_words": return String(quoteMaxWords)
        case "prompt_version": return String(promptVersion)
        case "chapter_word_limit": return String(chapterWordLimit)
        case "short_answer_grading": return shortAnswerGrading ? "true" : "false"
        case "tutor_meaning_floor": return String(format: "%.2f", tutorMeaningFloor)
        default: return ""
        }
    }
}
