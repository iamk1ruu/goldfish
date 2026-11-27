import Foundation

/// Decks. Every chapter belongs to one deck, and one deck is current.
extension GoldfishData {
    /// The deck Today, the Decks tab and Orla follow. Nil only when there are no decks yet.
    public var currentDeck: Deck? {
        decks.first { $0.id == currentDeckID } ?? decks.first
    }

    public func deck(_ id: String) -> Deck? {
        decks.first { $0.id == id }
    }

    /// A deck's chapters, newest first.
    public func chapters(inDeck deckID: String) -> [Chapter] {
        chapters.filter { $0.deckID == deckID }.sorted { $0.createdAt > $1.createdAt }
    }

    /// Makes sure every chapter has a deck and the current deck exists.
    /// Data saved before decks gets one deck: "Science" if all it holds is the sample chapter, otherwise "My deck".
    public mutating func ensureDecks() {
        if decks.isEmpty && !chapters.isEmpty {
            let onlySample = chapters.allSatisfy { $0.isSample }
            decks = [Deck(name: onlySample ? Deck.sampleDeckName : "My deck", color: onlySample ? .green : .blue)]
        }
        if let first = decks.first {
            let known = Set(decks.map { $0.id })
            for index in chapters.indices where !known.contains(chapters[index].deckID ?? "") {
                chapters[index].deckID = first.id
            }
        }
        if let current = currentDeckID, deck(current) == nil {
            currentDeckID = nil
        }
        if currentDeckID == nil {
            currentDeckID = decks.first?.id
        }
    }

    /// Adds a deck. A blank name becomes "New deck". With no colour, it takes the first one no deck uses.
    @discardableResult
    public mutating func addDeck(name: String, color: DeckColor? = nil, makeCurrent: Bool = true) -> Deck {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let deck = Deck(name: trimmed.isEmpty ? "New deck" : trimmed, color: color ?? DeckColor.firstUnused(by: decks))
        decks.append(deck)
        if makeCurrent || currentDeckID == nil {
            currentDeckID = deck.id
        }
        return deck
    }

    public mutating func editDeck(_ id: String, name: String, color: DeckColor) {
        guard let index = decks.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            decks[index].name = trimmed
        }
        decks[index].color = color
    }

    public mutating func setCurrentDeck(_ id: String) {
        if deck(id) != nil {
            currentDeckID = id
        }
    }

    /// Deletes a deck and every chapter in it. The last deck stays, so new chapters always have a home.
    public mutating func deleteDeck(_ id: String) {
        guard decks.count > 1, deck(id) != nil else { return }
        for chapter in chapters where chapter.deckID == id {
            deleteChapter(chapter.id)
        }
        decks.removeAll { $0.id == id }
        if currentDeckID == id {
            currentDeckID = decks.first?.id
        }
    }

    /// The deck for the sample chapter: an existing "Science" deck, or a new one.
    public mutating func sampleDeck() -> Deck {
        if let existing = decks.first(where: { $0.name == Deck.sampleDeckName }) {
            return existing
        }
        return addDeck(name: Deck.sampleDeckName, color: .green, makeCurrent: currentDeckID == nil)
    }

    /// The deck a new chapter goes into when none was given: the sample deck for the sample,
    /// otherwise the current deck, making "My deck" if there is none yet.
    mutating func homeDeckID(for chapter: Chapter) -> String {
        if let id = chapter.deckID, deck(id) != nil {
            return id
        }
        if chapter.isSample {
            return sampleDeck().id
        }
        if let current = currentDeck {
            return current.id
        }
        return addDeck(name: "My deck").id
    }
}
