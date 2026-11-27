import Foundation

/// Word and sentence helpers shared by grading, the own-words check and exam validation.
public enum TextTools {
    /// Lowercase words made of letters and digits. Any other character separates words.
    public static func words(_ text: String) -> [String] {
        TextNormalizer.normalize(text)
            .split(whereSeparator: { !($0.isLetter || $0.isNumber) })
            .map(String.init)
    }

    /// The words of `text` joined by single spaces.
    public static func wordSequence(_ text: String) -> String {
        words(text).joined(separator: " ")
    }

    /// True when `needle` appears in `haystack` as a run of whole words,
    /// ignoring case and punctuation.
    public static func containsWords(_ haystack: String, _ needle: String) -> Bool {
        WordText(haystack).contains(needle)
    }

    /// Splits text into sentences at `.`, `!` or `?` followed by a space or the end,
    /// and at every line break. Decimals such as 3.5 stay whole.
    public static func sentences(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        let characters = Array(text)
        for index in characters.indices {
            let character = characters[index]
            if character.isNewline {
                flush(&current, into: &result)
                continue
            }
            current.append(character)
            if character == "." || character == "!" || character == "?" {
                if index + 1 < characters.count {
                    if characters[index + 1].isWhitespace {
                        flush(&current, into: &result)
                    }
                } else {
                    flush(&current, into: &result)
                }
            }
        }
        flush(&current, into: &result)
        return result
    }

    private static func flush(_ current: inout String, into result: inout [String]) {
        let trimmed = current.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            result.append(trimmed)
        }
        current = ""
    }
}

/// A text prepared once for repeated whole-word searches.
public struct WordText {
    private let padded: String

    public init(_ text: String) {
        padded = " " + TextTools.wordSequence(text) + " "
    }

    public func contains(_ needle: String) -> Bool {
        let sequence = TextTools.wordSequence(needle)
        guard !sequence.isEmpty else { return false }
        return padded.contains(" " + sequence + " ")
    }
}

/// A hash that stays the same across launches, unlike `Hasher`.
public enum StableHash {
    public static func value(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }

    /// 16 lowercase hex digits.
    public static func hex(_ text: String) -> String {
        let digits = String(value(text), radix: 16)
        return String(repeating: "0", count: max(0, 16 - digits.count)) + digits
    }
}
