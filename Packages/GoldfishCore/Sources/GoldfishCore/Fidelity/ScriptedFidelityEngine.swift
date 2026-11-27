import Foundation

/// A stand-in fish with fixed behavior. It checks the Fish Check itself, and lets
/// the Diagnostics screen run on the Simulator, where Apple's model is unavailable.
/// Results from it say nothing about a real model.
public struct ScriptedFidelityEngine: FishEngine {
    public enum Persona: String, CaseIterable {
        /// Answers only from the lesson and quotes it exactly.
        case ideal
        /// Always answers correctly from prior knowledge.
        case leaky
        /// Follows the lesson but paraphrases its quotes.
        case sloppy
        /// Follows the lesson, but fills a missing fact from memory and cites a real sentence.
        case gapleak
        /// Always fails.
        case broken
    }

    public struct ScriptedFailure: Error, CustomStringConvertible {
        public let description: String
    }

    private let persona: Persona

    public init(persona: Persona) {
        self.persona = persona
    }

    public func reply(to prompt: String) async throws -> FishReply {
        if persona == .broken {
            throw ScriptedFailure(description: "Scripted failure")
        }
        guard let parts = FishPrompt.parts(of: prompt),
              let item = FidelityDataset.items.first(where: { $0.question == parts.question })
        else {
            throw ScriptedFailure(description: "Scripted fish only knows the Fish Check questions")
        }

        let lesson = parts.lesson
        let firstLine = lesson.split(whereSeparator: { $0.isNewline }).first.map { String($0) } ?? ""
        let taught = lesson.contains(item.sentence)
        let misled = lesson.contains(item.wrongSentence)
        let correct = FishPrompt.letter(for: item.correct)
        let planted = FishPrompt.letter(for: item.planted)

        func answer(_ letter: String, quoting quote: String) -> FishReply {
            FishReply(
                text: "QUOTE: \(quote)\nANSWER: \(letter)",
                tier: .scripted,
                modelVersion: "scripted-\(persona.rawValue)"
            )
        }
        func quoted(_ sentence: String) -> String {
            persona == .sloppy ? "In other words, \(sentence)" : sentence
        }

        if persona == .leaky {
            return answer(correct, quoting: firstLine)
        }
        if persona == .gapleak && !taught && !misled && !lesson.isEmpty {
            return answer(correct, quoting: firstLine)
        }
        if taught {
            return answer(correct, quoting: quoted(item.sentence))
        }
        if misled {
            return answer(planted, quoting: quoted(item.wrongSentence))
        }
        return answer("NONE", quoting: "NONE")
    }
}
