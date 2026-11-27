import Foundation
import NaturalLanguage
import GoldfishCore

/// Apple's built-in English sentence embedding, from the NaturalLanguage framework. It runs on the
/// iPhone with no model call and no connection, so Orla can find a passage that means what the student
/// asked even when it shares none of the chapter's words. Nil on a phone that lacks the embedding, and
/// then Orla searches by words only.
///
/// Not yet measured on the iPhone: how long a deck takes to embed (Diagnostics logs it) and how well it
/// ranks. The similarity floor is the Remote Config value `tutor_meaning_floor`.
struct AppleSentenceEmbedder: SentenceEmbedder {
    private let embedding: NLEmbedding

    init?() {
        guard let embedding = NLEmbedding.sentenceEmbedding(for: .english) else { return nil }
        self.embedding = embedding
    }

    func vector(for text: String) -> [Double]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return embedding.vector(for: trimmed)
    }
}
