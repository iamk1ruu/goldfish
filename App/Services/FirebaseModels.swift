import Foundation
import FirebaseAILogic
import GoldfishCore

// Every call to Firebase AI Logic lives in this file, so an SDK change is fixed in one place.
// The API shapes follow firebase.google.com/docs/ai-logic/hybrid/ios (checked 2026-11-13).
// The hybrid feature is Experimental, so if a line here stops compiling, check those pages first.

/// Where a text request may run.
enum ModelRoute: String, CaseIterable, Identifiable {
    /// Apple's model first, Gemini when it is unavailable. Production.
    case hybrid
    /// Apple's model only. Throws if unavailable, so failures cannot hide behind the cloud.
    case onDeviceOnly
    /// Gemini only.
    case cloudOnly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .hybrid: return "Hybrid (as shipped)"
        case .onDeviceOnly: return "Apple's model only"
        case .cloudOnly: return "Cloud only"
        }
    }
}

struct ModelText {
    let text: String
    let modelVersion: String

    var tier: FishTier {
        ModelVersion.tier(for: modelVersion)
    }
}

/// Single-turn text through a new session each time, so no history carries over.
enum FirebaseText {
    static func respond(to prompt: String, route: ModelRoute, cloudModel: String) async throws -> ModelText {
        let ai = FirebaseAI.firebaseAI(backend: .googleAI())
        let system = FirebaseAI.SystemLanguageModel.default
        let cloud = ai.geminiModel(name: cloudModel)

        switch route {
        case .hybrid:
            let session = ai.generativeModelSession(
                model: .hybridModel(primary: system, secondary: cloud)
            )
            // Low temperature on both models, so the fish answers the same way each time.
            let response = try await session.respond(
                to: prompt,
                options: .hybrid(
                    gemini: GenerationConfig(temperature: 0),
                    foundationModels: FirebaseAI.GenerationOptions(
                        sampling: .random(probabilityThreshold: 0.1),
                        temperature: 0.1
                    )
                )
            )
            let text: String = response.content
            return ModelText(text: text, modelVersion: ModelVersion.clean(String(describing: response.rawResponse.modelVersion)))

        case .onDeviceOnly:
            let session = ai.generativeModelSession(model: system)
            let response = try await session.respond(to: prompt)
            let text: String = response.content
            return ModelText(text: text, modelVersion: ModelVersion.clean(String(describing: response.rawResponse.modelVersion)))

        case .cloudOnly:
            let session = ai.generativeModelSession(model: cloud)
            let response = try await session.respond(to: prompt)
            let text: String = response.content
            return ModelText(text: text, modelVersion: ModelVersion.clean(String(describing: response.rawResponse.modelVersion)))
        }
    }
}

/// The fish, played by Firebase. Used by Pop Quizzes, the Fish Check and the fair exam check.
struct FirebaseFishEngine: FishEngine {
    let route: ModelRoute
    let cloudModel: String

    func reply(to prompt: String) async throws -> FishReply {
        let result = try await FirebaseText.respond(to: prompt, route: route, cloudModel: cloudModel)
        let version = result.modelVersion.isEmpty
            ? (route == .onDeviceOnly ? ModelVersion.appleOnDevice : cloudModel)
            : result.modelVersion
        return FishReply(text: result.text, tier: ModelVersion.tier(for: version), modelVersion: version)
    }
}

/// Error handling around the production fish:
/// a refusal or unavailable on-device model is retried once in the cloud, and a rate limit
/// is retried with backoff. Offline and App Check errors are passed up for the screen to explain.
struct ResilientFishEngine: FishEngine {
    let primary: FishEngine
    let cloud: FishEngine
    let log: @Sendable (String) -> Void

    func reply(to prompt: String) async throws -> FishReply {
        do {
            return try await primary.reply(to: prompt)
        } catch {
            let kind = ModelErrorKind.classify(String(describing: error))
            log("Fish call failed (\(kind.rawValue)): \(error)")
            switch kind {
            case .refused, .unavailable, .other:
                log("Retrying this question in the cloud")
                return try await Retry.withBackoff { try await cloud.reply(to: prompt) }
            case .rateLimited:
                return try await Retry.withBackoff { try await primary.reply(to: prompt) }
            case .offline, .appCheck:
                throw error
            }
        }
    }
}

/// Retries an operation when the cloud reports a rate limit (HTTP 429), waiting 1, 2 then 4 seconds.
enum Retry {
    static func withBackoff<T>(retries: Int = 3, _ operation: () async throws -> T) async throws -> T {
        var delay: UInt64 = 1_000_000_000
        var attempt = 0
        while true {
            do {
                return try await operation()
            } catch {
                attempt += 1
                guard attempt <= retries, ModelErrorKind.classify(String(describing: error)) == .rateLimited else {
                    throw error
                }
                try await Task.sleep(nanoseconds: delay)
                delay *= 2
            }
        }
    }
}

struct EmptyModelReply: Error, CustomStringConvertible {
    var description: String { "The model returned no text." }
}

/// Gemini writes the Hidden Exam as JSON matching a schema. Cloud only.
struct GeminiExamCompiler: ExamCompiler {
    let modelName: String

    func compile(title: String, chapterText: String, pdfData: Data?) async throws -> ExamDraft {
        let ai = FirebaseAI.firebaseAI(backend: .googleAI())
        let model = ai.generativeModel(
            modelName: modelName,
            generationConfig: GenerationConfig(
                responseMIMEType: "application/json",
                responseSchema: GeminiSchemas.exam
            )
        )
        let prompt = CloudPrompts.exam(title: title, chapterText: chapterText)
        let text: String? = try await Retry.withBackoff {
            if let pdf = pdfData {
                return try await model.generateContent(InlineDataPart(data: pdf, mimeType: "application/pdf"), prompt).text
            }
            return try await model.generateContent(prompt).text
        }
        guard let json = text, !json.isEmpty else { throw EmptyModelReply() }
        return try CloudJSON.decode(ExamDraft.self, from: json)
    }
}

/// Gemini writes the Report Card's three lists. Cloud only.
struct GeminiReportWriter: ReportWriter {
    let modelName: String

    func write(_ input: ReportInput) async throws -> ReportDraft {
        let ai = FirebaseAI.firebaseAI(backend: .googleAI())
        let model = ai.generativeModel(
            modelName: modelName,
            generationConfig: GenerationConfig(
                responseMIMEType: "application/json",
                responseSchema: GeminiSchemas.report
            )
        )
        let prompt = CloudPrompts.report(input)
        let text: String? = try await Retry.withBackoff {
            try await model.generateContent(prompt).text
        }
        guard let json = text, !json.isEmpty else { throw EmptyModelReply() }
        return try CloudJSON.decode(ReportDraft.self, from: json)
    }
}

/// Response schemas. Field names match `ExamDraft` and `ReportDraft` in GoldfishCore.
enum GeminiSchemas {
    static var exam: Schema {
        Schema.object(properties: [
            "concepts": .array(items: .object(properties: [
                "name": .string(),
                "summary": .string(),
                "whyQuestion": .string(),
                "questions": .array(items: .object(properties: [
                    "pool": .enumeration(values: ["practice", "final", "yourTurn"]),
                    "stem": .string(),
                    "options": .array(items: .string()),
                    "correctIndex": .integer(),
                    "keyTerms": .array(items: .string()),
                    "explanation": .string(),
                    "sourceQuote": .string(),
                    "modelSentence": .string(),
                ])),
            ])),
        ])
    }

    static var report: Schema {
        Schema.object(properties: [
            "explainedWell": .array(items: .string()),
            "misconceptions": .array(items: .string()),
            "reviewNext": .array(items: .string()),
        ])
    }
}

/// Apple's on-device model, as Firebase sees it.
enum AppleModelStatus {
    static var isAvailable: Bool {
        FirebaseAI.SystemLanguageModel.default.isAvailable
    }

    static var summary: String {
        switch FirebaseAI.SystemLanguageModel.default.availability {
        case .available:
            return "Available"
        case .unavailable(.deviceNotEligible):
            return "Unavailable: this iPhone can't run Apple Intelligence"
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Unavailable: turn on Apple Intelligence in Settings"
        case .unavailable(.modelNotReady):
            return "Unavailable: the model is still downloading"
        case let .unavailable(reason):
            return "Unavailable: \(reason)"
        }
    }
}
