import Foundation

/// Short codes for friends and shared chapters.
///
/// Codes are typed by hand or read off a screenshot, so letters and digits that look alike
/// (0 and O, 1, I and L) are left out. A friend code has 6 characters, about 887 million choices.
/// A chapter code has 8, about 850 billion, because anyone who has the code can read the chapter.
public enum ShareCode {
    public static let alphabet: [Character] = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
    public static let friendLength = 6
    public static let chapterLength = 8

    public static func make<G: RandomNumberGenerator>(length: Int, using generator: inout G) -> String {
        String((0..<max(1, length)).map { _ in alphabet.randomElement(using: &generator)! })
    }

    public static func make(length: Int) -> String {
        var generator = SystemRandomNumberGenerator()
        return make(length: length, using: &generator)
    }

    /// What the student typed or pasted, as a bare code: uppercase, with spaces, dashes and anything
    /// outside the alphabet removed. A misread character makes the code the wrong length, so it fails
    /// `isValid` instead of quietly turning into someone else's code.
    public static func normalize(_ raw: String) -> String {
        String(raw.uppercased().filter { alphabet.contains($0) })
    }

    /// Finds a code inside a pasted message such as "Learn Osmosis with me on Goldfish: ABCD-EFGH".
    /// In a message, only the dashed form counts, so an ordinary 8-letter word is never taken for a code.
    /// Text that is about as short as a code itself, such as "abcd efgh", is read as the code.
    public static func find(in text: String, length: Int) -> String? {
        let pieces = text.uppercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "-" })
        for piece in pieces.reversed() where piece.contains("-") && piece.count == length + 1 {
            let code = normalize(String(piece))
            if isValid(code, length: length) {
                return code
            }
        }
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).count <= length + 3 else { return nil }
        let whole = normalize(text)
        return isValid(whole, length: length) ? whole : nil
    }

    /// True when `code`, already normalized, is a code of this length.
    public static func isValid(_ code: String, length: Int) -> Bool {
        code.count == length && code.allSatisfy { alphabet.contains($0) }
    }

    /// "ABC-DEF" for a friend code, "ABCD-EFGH" for a chapter code.
    public static func display(_ code: String) -> String {
        guard code.count >= 6, code.count % 2 == 0 else { return code }
        let half = code.index(code.startIndex, offsetBy: code.count / 2)
        return "\(code[..<half])-\(code[half...])"
    }
}

/// JSON for documents stored in the cloud. Every Firestore document keeps its content as one JSON
/// string, so the Codable types here are the single source of truth and can be tested without Firebase.
public enum SocialJSON {
    public static func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: Data(text.utf8))
    }
}
