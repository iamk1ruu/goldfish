import Foundation

/// A deck's colour. Decks are named by the student, so a colour and the name's first letter mark them,
/// not a picture. Orange is left out because it belongs to Finn. App/UI/Theme.swift holds the light and dark values.
public enum DeckColor: String, Codable, CaseIterable {
    case blue
    case teal
    case green
    case yellow
    case red
    case pink
    case indigo
    case grey

    /// The colour's name, for VoiceOver and the colour picker.
    public var label: String {
        rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }

    /// The first colour no deck uses yet, so new decks look different without the student choosing.
    public static func firstUnused(by decks: [Deck]) -> DeckColor {
        let used = Set(decks.map { $0.color })
        return allCases.first { !used.contains($0) } ?? allCases[decks.count % allCases.count]
    }
}

/// A subject. Every chapter belongs to one deck, so subjects never mix.
/// One deck is the current deck: Today, the Decks tab and Orla all follow it.
public struct Deck: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var color: DeckColor

    public init(id: String = UUID().uuidString, name: String, color: DeckColor) {
        self.id = id
        self.name = name
        self.color = color
    }

    /// The name's first letter, shown on the deck's colour so decks differ by more than colour alone.
    public var initial: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).first.map { String($0).uppercased() } ?? "?"
    }

    /// The deck the built-in sample chapter (about goldfish) goes into.
    public static let sampleDeckName = "Science"

    enum CodingKeys: String, CodingKey {
        case id, name, color
    }

    /// Tolerates a missing or unknown colour, so one odd deck cannot stop the whole file loading.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "My deck"
        color = (try? c.decodeIfPresent(DeckColor.self, forKey: .color)) ?? .blue
    }
}
