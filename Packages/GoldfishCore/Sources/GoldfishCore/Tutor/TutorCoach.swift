import Foundation

/// What Orla says back: a hint, a question for the student, and the passage to reread.
/// She never gives the answer (the student explains, the app never does).
public struct TutorReply: Equatable {
    public var hint: String
    public var ask: String
    /// The passage she points to, always one of those she was given, so its text is the chapter's own.
    public var passage: Passage?

    public init(hint: String, ask: String, passage: Passage?) {
        self.hint = hint
        self.ask = ask
        self.passage = passage
    }
}

/// The single-turn prompt for Orla, the Socratic coach.
public enum TutorPrompt {
    /// How many passages she reads per question.
    public static let maxPassages = 3
    /// Apple's on-device model takes about 4,096 tokens in and out. A prompt above this estimate goes to the cloud.
    public static let onDeviceTokenBudget = 3_000

    /// `previous` is the student's question before this one. It is given only for a follow-up,
    /// so "Why doesn't it swell up?" reaches the model with what "it" means.
    public static func build(question: String, previous: String? = nil, deckName: String, fishName: String, passages: [Passage]) -> String {
        let numbered = passages.prefix(maxPassages).enumerated().map { offset, passage in
            "[\(offset + 1)] From \"\(passage.chapterTitle)\": \(passage.text)"
        }
        let earlier = previous?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let context = earlier.isEmpty ? "" : "\nThe student's question before this one, for context: \(earlier)"
        return """
        You are Orla, a wise old goldfish who coaches a student. The student is learning \(deckName) by teaching it to another fish, \(fishName). Help the student find the answer themselves.

        Rules:
        - Never state the answer. Never finish the student's sentence. Never list or guess answer options.
        - Use only the numbered passages below, which come from the student's own chapters.
        - Give one short hint that says where to look or what to notice, without giving the answer away.
        - Then ask the student one question that makes them think it through.
        - Choose the passage number that helps most.
        - If the passages do not cover the question, say so in the hint and ask which chapter it might be in.

        Reply in exactly this format, with no other text:
        HINT: <one or two sentences>
        ASK: <one question>
        PASSAGE: <a number>

        Passages:
        \(numbered.joined(separator: "\n"))
        \(context)
        Student's question: \(question.trimmingCharacters(in: .whitespacesAndNewlines))
        """
    }

    /// A rough token count: about four characters a token for English.
    public static func estimatedTokens(_ text: String) -> Int {
        text.count / 4 + 1
    }

    /// True when the prompt should fit Apple's on-device model. Otherwise ask the cloud directly.
    public static func fitsOnDevice(_ prompt: String) -> Bool {
        estimatedTokens(prompt) <= onDeviceTokenBudget
    }
}

/// Reads Orla's plain-text reply. Labels are matched without regard to case, a label's text may run
/// over several lines, and a missing or wrong passage number falls back to the best search match.
public enum TutorReplyParser {
    public static func parse(_ text: String, passages: [Passage]) -> TutorReply? {
        var fields: [String: String] = [:]
        var currentLabel: String?
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if let match = labelled(line) {
                currentLabel = match.label
                fields[match.label] = match.rest
            } else if let label = currentLabel, !line.isEmpty {
                fields[label] = [fields[label] ?? "", line].filter { !$0.isEmpty }.joined(separator: " ")
            }
        }
        let hint = clean(fields["HINT"] ?? "")
        let ask = clean(fields["ASK"] ?? "")
        guard !hint.isEmpty || !ask.isEmpty else { return nil }
        var passage = passages.first
        if let number = fields["PASSAGE"].flatMap(firstNumber), passages.indices.contains(number - 1) {
            passage = passages[number - 1]
        }
        return TutorReply(hint: hint, ask: ask, passage: passage)
    }

    private static func labelled(_ line: String) -> (label: String, rest: String)? {
        let stripped = line.trimmingCharacters(in: CharacterSet(charactersIn: "*#- "))
        for label in ["HINT", "ASK", "PASSAGE"] {
            if stripped.uppercased().hasPrefix(label + ":") {
                let rest = stripped.dropFirst(label.count + 1)
                return (label: label, rest: String(rest).trimmingCharacters(in: .whitespaces))
            }
        }
        return nil
    }

    private static func clean(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "*\"")))
    }

    private static func firstNumber(_ text: String) -> Int? {
        let digits = text.drop(while: { !$0.isNumber }).prefix(while: { $0.isNumber })
        return Int(String(digits))
    }
}

/// Keeps Orla Socratic. If her reply states the answer to a hidden exam question that matches the
/// student's question, the giveaway is replaced with a pointer to the passage. The student still has to
/// find it, and the exam still counts.
public enum AnswerGuard {
    public static let safeHint = "The answer is in the passage below. Read it, then put it in your own words."
    public static let safeAsk = "What does this passage say happens, and why?"

    /// For a follow-up, pass the earlier question and the new one together as `question`.
    /// Words are compared by their stems, so "filaments" and "filament" count as the same word.
    public static func check(_ reply: TutorReply, question: String, examQuestions: [Question]) -> TutorReply {
        let asked = stems(question)
        guard !asked.isEmpty else { return reply }
        var checked = reply
        for exam in examQuestions {
            let stem = stems(exam.stem)
            guard !stem.isEmpty else { continue }
            let shared = stem.intersection(asked).count
            // Only questions about the same thing as the student's question.
            guard shared >= 2 || Double(shared) / Double(stem.count) >= 0.5 else { continue }
            let answer = exam.correctOption
            // An answer the student already used in their question gives nothing away.
            let answerTerms = stems(answer)
            guard !answerTerms.isEmpty, !answerTerms.isSubset(of: asked) else { continue }
            if TextTools.containsWords(checked.hint, answer) {
                checked.hint = safeHint
            }
            if TextTools.containsWords(checked.ask, answer) {
                checked.ask = safeAsk
            }
        }
        return checked
    }

    private static func stems(_ text: String) -> Set<String> {
        Set(PassageIndex.terms(text).map(Stemmer.stem))
    }
}

/// Orla with no model, for the Simulator, screenshots and a phone without Firebase. She points to the
/// best passage and asks the student to explain it.
public enum ScriptedTutor {
    public static func reply(question: String, passages: [Passage], fishName: String) -> TutorReply {
        guard let best = passages.first else {
            return TutorReply(
                hint: "I couldn't find that in this deck's chapters.",
                ask: "Which chapter do you think covers it?",
                passage: nil
            )
        }
        // The first word of the question the passage also uses, in any form. A passage found by meaning
        // alone may share none, and then the hint stays general.
        let passageStems = Set(PassageIndex.terms(best.text).map(Stemmer.stem))
        let focus = PassageIndex.terms(question).first { passageStems.contains(Stemmer.stem($0)) }
        let hint = focus.map { "Look at the passage from \"\(best.chapterTitle)\". Find the sentence about \"\($0)\"." }
            ?? "Look at the passage from \"\(best.chapterTitle)\". One sentence there answers this."
        return TutorReply(hint: hint, ask: "How would you explain that to \(fishName) in one sentence?", passage: best)
    }
}
