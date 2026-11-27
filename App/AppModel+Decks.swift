import Foundation
import GoldfishCore

/// What Orla said to one question, and where it ran.
struct TutorAnswer: Identifiable {
    let id = UUID()
    let question: String
    let deckName: String
    let reply: TutorReply
    /// Nil when no model was asked: the search found nothing, so Orla said so herself.
    let tier: FishTier?
    let latencyMs: Int
    /// The question was a short follow-up, searched together with the one before it.
    var followUp = false
    /// How the passage she points to was found.
    var foundBy: FoundBy?
    /// What was searched: the question, or for a follow-up the question before it and this one.
    /// The next follow-up builds on it.
    var searchedText = ""

    enum FoundBy {
        case words
        case meaning
        case both
    }

    /// One line under her reply on how the search went, or nil when there is nothing to add.
    var searchNote: String? {
        var parts: [String] = []
        if followUp {
            parts.append("Searched with your last question")
        }
        if foundBy == .meaning {
            parts.append("Found by meaning, not by your words")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// One deck's passages, embedded once, and the embedding that searches them.
struct TutorSearchCache {
    let key: String
    let index: PassageIndex
    let embedder: AppleSentenceEmbedder?
}

// Decks, the forgiving fire and Orla.
extension AppModel {
    // MARK: Decks

    var currentDeck: Deck? {
        data.currentDeck
    }

    func chapters(inDeck deckID: String) -> [Chapter] {
        data.chapters(inDeck: deckID)
    }

    func dueChapters(inDeck deckID: String) -> [Chapter] {
        chapters(inDeck: deckID).filter { Tides.isDue(data.chapterProgress[$0.id], today: today) }
    }

    /// Decks other than the current one with Fresh Water due, for the nudge on Today.
    func otherDecksWithDue() -> [(deck: Deck, due: Int)] {
        data.decks.compactMap { deck -> (deck: Deck, due: Int)? in
            guard deck.id != currentDeck?.id else { return nil }
            let due = dueChapters(inDeck: deck.id).count
            return due > 0 ? (deck, due) : nil
        }
    }

    func setCurrentDeck(_ deckID: String) {
        guard deckID != data.currentDeckID else { return }
        data.setCurrentDeck(deckID)
        scheduleSave()
    }

    @discardableResult
    func addDeck(name: String, color: DeckColor) -> Deck {
        let deck = data.addDeck(name: name, color: color)
        scheduleSave()
        return deck
    }

    func editDeck(_ deckID: String, name: String, color: DeckColor) {
        data.editDeck(deckID, name: name, color: color)
        scheduleSave()
    }

    /// Deletes a deck and its chapters. The last deck stays.
    func deleteDeck(_ deckID: String) {
        for chapter in chapters(inDeck: deckID) {
            invalidateChecker(chapter.id)
        }
        data.deleteDeck(deckID)
        path = []
        scheduleSave()
    }

    // MARK: The fire

    /// The forgiving streak. Counts days Finn was taught. One missed day leaves embers.
    var fire: FireStreak {
        FireStreak.compute(data.teachingDays, today: today)
    }

    // MARK: Orla

    /// The deck's passages, cut and embedded off the main thread the first time Orla is asked about
    /// the deck, then kept until its chapters change. Without Apple's sentence embedding the index
    /// searches by words only.
    func tutorSearch(deck: Deck, chapters: [Chapter]) async -> TutorSearchCache {
        let key = deck.id + "|" + chapters.map { "\($0.id):\($0.sourceText.count)" }.joined(separator: ",")
        if let cached = tutorSearchCache, cached.key == key {
            return cached
        }
        let started = Date()
        let built = await Task.detached(priority: .userInitiated) { () -> TutorSearchCache in
            let plain = PassageIndex(chapters: chapters)
            guard let embedder = AppleSentenceEmbedder() else {
                return TutorSearchCache(key: key, index: plain, embedder: nil)
            }
            return TutorSearchCache(key: key, index: plain.embedded(with: embedder), embedder: embedder)
        }.value
        tutorSearchCache = built
        let meaning = built.index.searchesMeaning ? "on" : "off (no sentence embedding)"
        diagnostics.log("Orla read \(deck.name): \(built.index.passages.count) passages, meaning search \(meaning), \(Self.ms(since: started)) ms")
        return built
    }

    /// Orla, the Socratic tutor. She searches the current deck's chapters on this iPhone, by words
    /// and by meaning, then asks Apple's on-device model for a hint, a question back and the passage
    /// to reread. The cloud answers when the prompt is too long for the iPhone or Apple's model is
    /// unavailable. She never gives the answer: the prompt forbids it, and AnswerGuard replaces a reply that
    /// states a hidden exam answer.
    ///
    /// `previous` is what was searched for the question before, so a short follow-up such as
    /// "Why doesn't it swell up?" is searched together with it.
    func askOrla(_ question: String, previous: String? = nil) async throws -> TutorAnswer {
        guard let deck = currentDeck else {
            throw GoldfishError(description: "Make a deck first, then add a chapter to it.")
        }
        let chapters = self.chapters(inDeck: deck.id)
        let started = Date()
        let cache = await tutorSearch(deck: deck, chapters: chapters)
        let floor = settings.tutorMeaningFloor
        let search = await Task.detached(priority: .userInitiated) {
            cache.index.find(
                question, previous: previous, embedder: cache.embedder,
                meaningFloor: floor, limit: TutorPrompt.maxPassages
            )
        }.value
        let passages = search.passages
        let earlier = search.followUp ? previous : nil
        let searchedText = [earlier, question].compactMap { $0 }.joined(separator: " ")
        let examQuestions = chapters.flatMap { exam($0.id)?.questions ?? [] }
        let how = (search.searchedMeaning ? String(format: "best meaning %.2f", search.bestSimilarity ?? 0) : "words only")
            + (search.followUp ? ", follow-up" : "")

        func answer(_ reply: TutorReply, tier: FishTier?) -> TutorAnswer {
            var result = TutorAnswer(
                question: question, deckName: deck.name, reply: reply, tier: tier, latencyMs: Self.ms(since: started)
            )
            result.followUp = search.followUp
            result.searchedText = searchedText
            if let passage = reply.passage, let hit = search.hits.first(where: { $0.passage == passage }) {
                let found: TutorAnswer.FoundBy = hit.matchedWords && hit.matchedMeaning
                    ? .both
                    : (hit.matchedMeaning ? .meaning : .words)
                result.foundBy = found
            }
            return result
        }

        // Nothing in the deck matches, or there is no model to ask: Orla answers from the search alone.
        if passages.isEmpty || usesScriptedFish {
            diagnostics.log("Orla searched without a model: \(passages.count) passage(s), \(how)")
            let reply = ScriptedTutor.reply(question: searchedText, passages: passages, fishName: fishName)
            return answer(reply, tier: passages.isEmpty ? nil : .scripted)
        }

        let prompt = TutorPrompt.build(
            question: question, previous: earlier, deckName: deck.name, fishName: fishName, passages: passages
        )
        let cloudModel = settings.fishCloudModel
        let engine: FishEngine = TutorPrompt.fitsOnDevice(prompt)
            ? ResilientFishEngine(
                primary: FirebaseFishEngine(route: .hybrid, cloudModel: cloudModel),
                cloud: FirebaseFishEngine(route: .cloudOnly, cloudModel: cloudModel),
                log: logger()
            )
            : FirebaseFishEngine(route: .cloudOnly, cloudModel: cloudModel)

        do {
            let reply = try await engine.reply(to: prompt)
            // An unreadable reply still gets the student to the right passage.
            let parsed = TutorReplyParser.parse(reply.text, passages: passages)
                ?? ScriptedTutor.reply(question: searchedText, passages: passages, fishName: fishName)
            // A follow-up is checked with the question before it, so "Why?" cannot draw out an answer either.
            let checked = AnswerGuard.check(parsed, question: searchedText, examQuestions: examQuestions)
            diagnostics.record(ModelCallRecord(
                lane: "tutor", tier: reply.tier, modelVersion: reply.modelVersion, latencyMs: Self.ms(since: started),
                ok: true, detail: "\(passages.count) passage(s), \(how), \(TutorPrompt.estimatedTokens(prompt)) tokens"
            ))
            return answer(checked, tier: reply.tier)
        } catch {
            diagnostics.record(ModelCallRecord(
                lane: "tutor", tier: nil, modelVersion: "", latencyMs: Self.ms(since: started),
                ok: false, detail: String(describing: error)
            ))
            throw GoldfishError(description: ModelErrorKind.classify(String(describing: error)).userMessage)
        }
    }
}
