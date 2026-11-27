import Foundation

/// The exam as the cloud writes it, before validation. Field names match the response schema.
/// Every field decodes leniently, so one malformed question is dropped instead of the whole exam.
public struct ExamDraft: Codable, Equatable {
    public var concepts: [ConceptDraft]

    public init(concepts: [ConceptDraft]) {
        self.concepts = concepts
    }

    enum CodingKeys: String, CodingKey {
        case concepts
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        concepts = try c.decodeIfPresent([ConceptDraft].self, forKey: .concepts) ?? []
    }
}

public struct ConceptDraft: Codable, Equatable {
    public var name: String
    public var summary: String
    public var whyQuestion: String
    public var questions: [QuestionDraft]

    public init(name: String, summary: String, whyQuestion: String, questions: [QuestionDraft]) {
        self.name = name
        self.summary = summary
        self.whyQuestion = whyQuestion
        self.questions = questions
    }

    enum CodingKeys: String, CodingKey {
        case name, summary, whyQuestion, questions
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        whyQuestion = try c.decodeIfPresent(String.self, forKey: .whyQuestion) ?? ""
        questions = try c.decodeIfPresent([QuestionDraft].self, forKey: .questions) ?? []
    }
}

public struct QuestionDraft: Codable, Equatable {
    public var pool: String
    public var stem: String
    public var options: [String]
    public var correctIndex: Int
    public var keyTerms: [String]
    public var explanation: String
    public var sourceQuote: String
    public var modelSentence: String

    public init(
        pool: String, stem: String, options: [String], correctIndex: Int, keyTerms: [String],
        explanation: String, sourceQuote: String, modelSentence: String
    ) {
        self.pool = pool
        self.stem = stem
        self.options = options
        self.correctIndex = correctIndex
        self.keyTerms = keyTerms
        self.explanation = explanation
        self.sourceQuote = sourceQuote
        self.modelSentence = modelSentence
    }

    enum CodingKeys: String, CodingKey {
        case pool, stem, options, correctIndex, keyTerms, explanation, sourceQuote, modelSentence
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pool = (try? c.decodeIfPresent(String.self, forKey: .pool)) ?? ""
        stem = (try? c.decodeIfPresent(String.self, forKey: .stem)) ?? ""
        options = (try? c.decodeIfPresent([String].self, forKey: .options)) ?? []
        correctIndex = (try? c.decodeIfPresent(Int.self, forKey: .correctIndex)) ?? -1
        keyTerms = (try? c.decodeIfPresent([String].self, forKey: .keyTerms)) ?? []
        explanation = (try? c.decodeIfPresent(String.self, forKey: .explanation)) ?? ""
        sourceQuote = (try? c.decodeIfPresent(String.self, forKey: .sourceQuote)) ?? ""
        modelSentence = (try? c.decodeIfPresent(String.self, forKey: .modelSentence)) ?? ""
    }
}

/// The three lists the cloud writes for the Report Card. Counts are computed in code.
public struct ReportDraft: Codable, Equatable {
    public var explainedWell: [String]
    public var misconceptions: [String]
    public var reviewNext: [String]

    public init(explainedWell: [String], misconceptions: [String], reviewNext: [String]) {
        self.explainedWell = explainedWell
        self.misconceptions = misconceptions
        self.reviewNext = reviewNext
    }

    enum CodingKeys: String, CodingKey {
        case explainedWell, misconceptions, reviewNext
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        explainedWell = (try? c.decodeIfPresent([String].self, forKey: .explainedWell)) ?? []
        misconceptions = (try? c.decodeIfPresent([String].self, forKey: .misconceptions)) ?? []
        reviewNext = (try? c.decodeIfPresent([String].self, forKey: .reviewNext)) ?? []
    }
}

/// Reads JSON from a model reply, tolerating code fences and text around the object.
public enum CloudJSON {
    public static func extractObject(_ text: String) -> String {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else {
            return text
        }
        return String(text[start...end])
    }

    public static func decode<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(extractObject(text).utf8))
    }
}

/// Writes the Hidden Exam. Implemented by Gemini in the app, and by fixtures in tests.
public protocol ExamCompiler {
    func compile(title: String, chapterText: String, pdfData: Data?) async throws -> ExamDraft
}

/// Writes the Report Card lists.
public protocol ReportWriter {
    func write(_ input: ReportInput) async throws -> ReportDraft
}
