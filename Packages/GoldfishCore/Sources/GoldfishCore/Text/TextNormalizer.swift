import Foundation

/// Normalizes text so a quote from the fish can be compared with the lesson.
public enum TextNormalizer {
    /// Lowercases, straightens curly quotes and collapses whitespace to single spaces.
    public static func normalize(_ text: String) -> String {
        let straightened = text
            .lowercased()
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")
        return straightened
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    /// Normalizes a quote and drops surrounding quotation marks and end punctuation.
    public static func cleanQuote(_ quote: String) -> String {
        let leadingJunk: Set<Character> = ["\"", "'", "`", " "]
        let trailingJunk: Set<Character> = ["\"", "'", "`", " ", ".", ",", ";", ":", "!", "?"]
        var slice = Substring(normalize(quote))
        while let first = slice.first, leadingJunk.contains(first) {
            slice = slice.dropFirst()
        }
        while let last = slice.last, trailingJunk.contains(last) {
            slice = slice.dropLast()
        }
        return String(slice)
    }

    public static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }
}
