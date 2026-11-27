import Foundation

/// Flags lesson sentences that copy a run of words from the chapter.
/// Flagged sentences do not count, and the fish never sees them, until they are rewritten.
public struct OwnWordsChecker {
    public static let defaultRunLength = 8

    public let runLength: Int
    private let runs: Set<String>

    public init(chapterText: String, runLength: Int = 8) {
        self.runLength = max(2, runLength)
        let words = TextTools.words(chapterText)
        var runs = Set<String>()
        if words.count >= self.runLength {
            for start in 0...(words.count - self.runLength) {
                runs.insert(words[start..<(start + self.runLength)].joined(separator: " "))
            }
        }
        self.runs = runs
    }

    /// True when the sentence shares a run of `runLength` words with the chapter.
    public func isCopied(_ sentence: String) -> Bool {
        let words = TextTools.words(sentence)
        guard words.count >= runLength else { return false }
        for start in 0...(words.count - runLength) {
            if runs.contains(words[start..<(start + runLength)].joined(separator: " ")) {
                return true
            }
        }
        return false
    }

    public func copiedSentences(in text: String) -> [String] {
        TextTools.sentences(text).filter { isCopied($0) }
    }
}

/// Blocks pasting more than a short phrase into the Bowl.
/// Typing and dictation add a few words at a time, so a large jump means a paste.
public enum PasteGuard {
    public static let maxInsertedWords = 12

    public static func isLargeInsert(old: String, new: String) -> Bool {
        guard new.count > old.count else { return false }
        let added = TextNormalizer.wordCount(new) - TextNormalizer.wordCount(old)
        return added > maxInsertedWords
    }
}
