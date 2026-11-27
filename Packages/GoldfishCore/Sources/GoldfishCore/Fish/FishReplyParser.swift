import Foundation

/// Reads the fish's two-line reply. Tolerant of case, markdown decoration,
/// extra chatter, and both parts arriving on one line.
public enum FishReplyParser {
    public static func parse(_ raw: String, optionCount: Int = 4) -> ParsedFishReply? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if isNoneWord(trimmed) {
            return ParsedFishReply(choice: .notTaught, quote: "")
        }

        // The last ANSWER label wins, in case the model repeats the instructions first.
        guard let answerLabel = raw.range(of: "ANSWER:", options: [.caseInsensitive, .backwards]) else {
            return nil
        }
        let answerText = firstLine(of: raw[answerLabel.upperBound...])
        guard let choice = parseChoice(answerText, optionCount: optionCount) else {
            return nil
        }
        if choice == .notTaught {
            return ParsedFishReply(choice: .notTaught, quote: "")
        }

        var quote = ""
        if let quoteLabel = raw.range(of: "QUOTE:", options: [.caseInsensitive]) {
            let end = quoteLabel.upperBound <= answerLabel.lowerBound ? answerLabel.lowerBound : raw.endIndex
            quote = stripDecoration(firstLine(of: raw[quoteLabel.upperBound..<end]))
        }
        if isNoneWord(quote) {
            quote = ""
        }
        return ParsedFishReply(choice: choice, quote: quote)
    }

    private static func firstLine<S: StringProtocol>(of text: S) -> String {
        for line in text.split(whereSeparator: { $0.isNewline }) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return ""
    }

    private static func stripDecoration(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet(charactersIn: "*`_ \t"))
    }

    private static func isNoneWord(_ text: String) -> Bool {
        let cleaned = TextNormalizer.cleanQuote(stripDecoration(text))
        return cleaned == "none" || cleaned == "n/a"
    }

    private static func parseChoice(_ text: String, optionCount: Int) -> FishChoice? {
        let separators = CharacterSet(charactersIn: " \t()[]<>.,:;*`\"'")
        let tokens = text.uppercased()
            .components(separatedBy: separators)
            .filter { !$0.isEmpty }

        for token in tokens {
            if token.hasPrefix("NONE") || token == "N/A" {
                return .notTaught
            }
            guard token.count == 1, let scalar = token.unicodeScalars.first else {
                continue
            }
            let index = Int(scalar.value) - 65  // "A" is 65
            if index >= 0 && index < optionCount {
                return .option(index)
            }
        }
        return nil
    }
}
