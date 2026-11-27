import Foundation

/// The go or no-go test for grading what the student types before seeing the options.
///
/// Twelve typed answers to four questions, each with the grade a teacher would give: for every question
/// one answer that means the key, one that is partly right or vague, and one that is wrong. Graded recall
/// is turned on only if the model gives the expected grade to at least 10 of the 12 and makes no harmful
/// mistake, which is calling a wrong answer a match or a right answer a miss. Run it with Apple's model
/// only, from Diagnostics, so the cloud cannot hide a failure.
public enum GradingCheck {
    /// One typed answer and the grade it should get.
    public struct Case: Equatable {
        public let id: String
        public let question: Question
        public let answer: String
        public let expected: ShortAnswerGrade
    }

    /// What the model said about one case.
    public struct Trial: Equatable {
        public let caseID: String
        public let expected: ShortAnswerGrade
        /// Nil when the reply could not be read or the call failed.
        public let got: ShortAnswerGrade?
        public let raw: String
        public let latencyMs: Int
        public let modelVersion: String

        public init(caseID: String, expected: ShortAnswerGrade, got: ShortAnswerGrade?, raw: String, latencyMs: Int, modelVersion: String) {
            self.caseID = caseID
            self.expected = expected
            self.got = got
            self.raw = raw
            self.latencyMs = latencyMs
            self.modelVersion = modelVersion
        }

        public var agrees: Bool {
            got == expected
        }

        /// A wrong answer called a match, or a right answer called a miss. A "partly right" is never harmful.
        public var harmful: Bool {
            (expected == .miss && got == .match) || (expected == .match && got == .miss)
        }
    }

    public struct Result: Equatable {
        public let trials: [Trial]

        public init(trials: [Trial]) {
            self.trials = trials
        }

        public var agreed: Int {
            trials.filter(\.agrees).count
        }

        public var harmful: Int {
            trials.filter(\.harmful).count
        }

        /// Every case ran, at least `required` agreed, and none was harmful.
        public var passed: Bool {
            trials.count == GradingCheck.cases.count && agreed >= GradingCheck.required && harmful == 0
        }

        public var modelVersion: String {
            trials.first { !$0.modelVersion.isEmpty }?.modelVersion ?? ""
        }

        public var latencyP50: Int {
            let sorted = trials.map(\.latencyMs).sorted()
            return sorted.isEmpty ? 0 : sorted[sorted.count / 2]
        }
    }

    /// How many of the twelve must agree.
    public static let required = 10

    /// Asks the engine to grade every case, in order. Errors count as unreadable, so one failed call
    /// cannot pass the check.
    public static func run(
        engine: FishEngine,
        shouldStop: @escaping () -> Bool = { false },
        onProgress: @escaping (_ done: Int, _ total: Int) -> Void = { _, _ in }
    ) async -> Result {
        var trials: [Trial] = []
        for (offset, item) in cases.enumerated() {
            if shouldStop() { break }
            let started = Date()
            do {
                let reply = try await engine.reply(to: ShortAnswerPrompt.build(question: item.question, answer: item.answer))
                trials.append(Trial(
                    caseID: item.id, expected: item.expected, got: ShortAnswerPrompt.parse(reply.text),
                    raw: reply.text, latencyMs: Self.ms(since: started), modelVersion: reply.modelVersion
                ))
            } catch {
                trials.append(Trial(
                    caseID: item.id, expected: item.expected, got: nil,
                    raw: "Error: \(error)", latencyMs: Self.ms(since: started), modelVersion: ""
                ))
            }
            onProgress(offset + 1, cases.count)
        }
        return Result(trials: trials)
    }

    /// A plain-text summary to copy from Diagnostics.
    public static func report(_ result: Result, source: String, device: String, date: Date) -> String {
        var lines = [
            "Grading Check",
            "Source: \(source)",
            "Device: \(device)",
            "Model: \(result.modelVersion.isEmpty ? "unknown" : result.modelVersion)",
            "Date: \(ISO8601DateFormatter().string(from: date))",
            "",
            "Agreed: \(result.agreed) of \(cases.count) (needs \(required))",
            "Harmful mistakes: \(result.harmful) (needs 0)",
            "Median time: \(result.latencyP50) ms",
            "Verdict: \(result.passed ? "PASS. Graded recall can go on." : "FAIL. Graded recall stays off.")",
            "",
        ]
        for trial in result.trials {
            let got = trial.got?.rawValue ?? "unreadable"
            let mark = trial.agrees ? "ok" : (trial.harmful ? "HARMFUL" : "differs")
            let raw = trial.raw.replacingOccurrences(of: "\n", with: " ").prefix(60)
            lines.append("\(trial.caseID): expected \(trial.expected.rawValue), got \(got) [\(mark)] \(trial.latencyMs) ms \"\(raw)\"")
        }
        return lines.joined(separator: "\n")
    }

    private static func ms(since date: Date) -> Int {
        Int(Date().timeIntervalSince(date) * 1000)
    }

    // MARK: The cases

    private static func question(_ id: String, _ stem: String, key: String, explanation: String) -> Question {
        Question(
            id: "grading-\(id)", conceptID: "grading", stem: stem, options: [key], correctIndex: 0,
            keyTerms: [], explanation: explanation, sourceQuote: "", modelSentence: "", pool: .yourTurn
        )
    }

    static let osmosis = question(
        "osmosis", "Which way does water move across a membrane in osmosis?",
        key: "Toward the side with more dissolved solute",
        explanation: "Water moves from the side with less solute to the side with more, which evens out the concentration."
    )
    static let activeTransport = question(
        "active", "What does active transport use that diffusion does not?",
        key: "Energy from the cell, usually ATP",
        explanation: "Active transport moves substances against their concentration gradient, which costs the cell energy."
    )
    static let urine = question(
        "urine", "Why does a freshwater fish make large amounts of dilute urine?",
        key: "To get rid of the water that keeps entering its body by osmosis",
        explanation: "Its body fluids are saltier than the water around it, so water seeps in through the gills and must be removed."
    )
    static let channels = question(
        "channels", "What do channel proteins do?",
        key: "Let one kind of molecule or ion pass through the membrane",
        explanation: "Each channel protein forms a tunnel that lets a single kind of substance through while blocking the rest."
    )

    public static let cases: [Case] = [
        Case(id: "osmosis-match", question: osmosis, answer: "water goes to the side where more stuff is dissolved", expected: .match),
        Case(id: "osmosis-partial", question: osmosis, answer: "it moves across the membrane", expected: .partial),
        Case(id: "osmosis-miss", question: osmosis, answer: "toward the side with less salt in it", expected: .miss),
        Case(id: "active-match", question: activeTransport, answer: "it needs energy, ATP", expected: .match),
        Case(id: "active-partial", question: activeTransport, answer: "something from the cell", expected: .partial),
        Case(id: "active-miss", question: activeTransport, answer: "it uses water", expected: .miss),
        Case(id: "urine-match", question: urine, answer: "water keeps coming in through its gills by osmosis so it has to pee the extra out", expected: .match),
        Case(id: "urine-partial", question: urine, answer: "because of osmosis", expected: .partial),
        Case(id: "urine-miss", question: urine, answer: "to get rid of extra salt", expected: .miss),
        Case(id: "channels-match", question: channels, answer: "they make a tunnel so one certain molecule can get through the membrane", expected: .match),
        Case(id: "channels-partial", question: channels, answer: "they let things through", expected: .partial),
        Case(id: "channels-miss", question: channels, answer: "they make energy for the cell", expected: .miss),
    ]
}
