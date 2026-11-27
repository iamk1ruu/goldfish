import Foundation

/// Where a fish reply was produced.
public enum FishTier: String, Codable, Equatable, CaseIterable {
    case onDevice
    case cloud
    case scripted

    /// The wording on the tier badge.
    public var label: String {
        switch self {
        case .onDevice: return "On this iPhone"
        case .cloud: return "Cloud"
        case .scripted: return "Scripted"
        }
    }
}

/// The raw reply from whichever model played the fish.
public struct FishReply: Codable, Equatable {
    public let text: String
    public let tier: FishTier
    public let modelVersion: String

    public init(text: String, tier: FishTier, modelVersion: String) {
        self.text = text
        self.tier = tier
        self.modelVersion = modelVersion
    }
}

/// Anything that can answer a fish prompt: Apple's model, Gemini, or a script.
public protocol FishEngine {
    func reply(to prompt: String) async throws -> FishReply
}

/// What the fish chose for one question.
public enum FishChoice: Codable, Equatable {
    case option(Int)
    case notTaught
}

/// A fish reply after parsing, before any grading.
public struct ParsedFishReply: Codable, Equatable {
    public let choice: FishChoice
    public let quote: String

    public init(choice: FishChoice, quote: String) {
        self.choice = choice
        self.quote = quote
    }
}

/// How a fish answer is graded.
public enum FishVerdict: String, Codable, Equatable {
    /// Right option, backed by a real sentence from the lesson.
    case correct
    /// Wrong option, backed by a real sentence from the lesson: the lesson misled the fish.
    case mixUp
    /// Not taught, or no lesson sentence backs the choice.
    case gap

    public var label: String {
        switch self {
        case .correct: return "Correct"
        case .mixUp: return "Mix-up"
        case .gap: return "Gap"
        }
    }
}

/// Reads the model version Firebase reports and maps it to a tier.
public enum ModelVersion {
    /// The value Firebase reports for Apple's on-device model.
    public static let appleOnDevice = "apple-foundation-models-system-language-model"

    /// Cleans a value printed with `String(describing:)`, which may arrive as `Optional("...")`.
    /// This keeps the app working whether the SDK types the version as optional or not.
    public static func clean(_ described: String) -> String {
        var text = described
        if text.hasPrefix("Optional(") && text.hasSuffix(")") {
            text = String(text.dropFirst("Optional(".count).dropLast())
        }
        if text.count >= 2 && text.hasPrefix("\"") && text.hasSuffix("\"") {
            text = String(text.dropFirst().dropLast())
        }
        return text == "nil" ? "" : text
    }

    public static func tier(for version: String) -> FishTier {
        version.lowercased().hasPrefix("apple-") ? .onDevice : .cloud
    }
}
