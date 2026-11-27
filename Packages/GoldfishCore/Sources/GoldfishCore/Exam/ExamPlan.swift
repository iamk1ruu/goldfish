import Foundation

/// One part of an uploaded document, small enough for the fish to learn as one chapter.
public struct DocumentPart: Equatable {
    /// 1-based.
    public let number: Int
    /// How many parts the document makes.
    public let count: Int
    public let title: String
    public let text: String
    public let words: Int

    /// How many concepts the cloud should find in this part. See `ExamPlan.conceptTarget`.
    public var conceptTarget: Int {
        ExamPlan.conceptTarget(words: words)
    }
}

/// Covering a whole document.
///
/// Apple's on-device model reads about 4,096 tokens and the Bowl holds 600 words, so the fish can only
/// learn so much at once. A long document therefore becomes several chapters in the same deck, cut at its
/// section headings. Each part gets concepts in proportion to its length rather than a fixed number, and
/// `CoverageCheck` makes sure every passage of the part has a question tied to it.
public enum ExamPlan {
    /// About how long one chapter is. A part closes at the next heading after 60% of this, or at the next
    /// paragraph once it is full.
    public static let partWords = 1_500
    /// A leftover shorter than this joins the part before it.
    public static let minimumPartWords = 300
    /// About one concept per this many words.
    public static let wordsPerConcept = 150
    public static let conceptRange = 3...10

    public static func conceptTarget(words: Int) -> Int {
        let estimate = Int((Double(words) / Double(wordsPerConcept)).rounded())
        return min(conceptRange.upperBound, max(conceptRange.lowerBound, estimate))
    }

    /// Splits a document into chapter-sized parts. The text keeps its own line breaks, so the reader shows
    /// it as written. A short document is one part with the document's title.
    public static func parts(title: String, text: String) -> [DocumentPart] {
        let units = self.units(text)
        var groups: [[Unit]] = []
        var current: [Unit] = []
        var words = 0
        for unit in units {
            let breakAtHeading = unit.isHeading && words >= partWords * 3 / 5
            // Lines are paragraphs. A very long line was cut into sentences, so a part can end at one of those too.
            let breakWhenFull = words >= partWords && unit.words > 0
            if !current.isEmpty && (breakAtHeading || breakWhenFull) {
                groups.append(current)
                current = []
                words = 0
            }
            current.append(unit)
            words += unit.words
        }
        if !current.isEmpty {
            if words < minimumPartWords, let last = groups.last {
                groups[groups.count - 1] = last + current
            } else {
                groups.append(current)
            }
        }

        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseTitle = cleanTitle.isEmpty ? "Untitled chapter" : cleanTitle
        return groups.enumerated().map { offset, group in
            let partText = join(group).trimmingCharacters(in: .whitespacesAndNewlines)
            let heading = group.first { $0.words > 0 }.flatMap { $0.isHeading ? $0.text.trimmingCharacters(in: .whitespaces) : nil }
            let partTitle: String
            if groups.count == 1 {
                partTitle = baseTitle
            } else if let heading = heading, heading.lowercased() != baseTitle.lowercased() {
                partTitle = "\(baseTitle) \(offset + 1): \(heading)"
            } else {
                partTitle = "\(baseTitle) \(offset + 1)"
            }
            return DocumentPart(
                number: offset + 1, count: groups.count, title: partTitle,
                text: partText, words: group.reduce(0) { $0 + $1.words }
            )
        }
    }

    /// A line of the document, or one sentence of a very long line. PDF text often puts a whole page on one
    /// line, so long lines are cut at sentences to let a part end in the middle of them.
    private struct Unit {
        let text: String
        let words: Int
        /// True for the first piece of a line. Later pieces of the same line follow with a space.
        let startsLine: Bool
        let isHeading: Bool
    }

    private static func units(_ text: String) -> [Unit] {
        var units: [Unit] = []
        for line in text.components(separatedBy: .newlines) {
            let count = TextTools.words(line).count
            if count <= 200 {
                units.append(Unit(text: line, words: count, startsLine: true, isHeading: PassageIndex.isHeading(line, wordCount: count)))
                continue
            }
            for (offset, sentence) in TextTools.sentences(line).enumerated() {
                units.append(Unit(text: sentence, words: TextTools.words(sentence).count, startsLine: offset == 0, isHeading: false))
            }
        }
        return units
    }

    private static func join(_ units: [Unit]) -> String {
        var result = ""
        for (offset, unit) in units.enumerated() {
            if offset > 0 {
                result += unit.startsLine ? "\n" : " "
            }
            result += unit.text
        }
        return result
    }
}

/// How much of a chapter its Hidden Exam reaches: passages with at least one question quoting them.
public struct ExamCoverage: Codable, Equatable {
    /// Passages long enough to count. A lone heading does not.
    public var passages: Int
    public var covered: Int

    public init(passages: Int, covered: Int) {
        self.passages = passages
        self.covered = covered
    }

    public var isComplete: Bool {
        covered >= passages
    }
}

/// Checks that every passage of a chapter has a question tied to it, through the question's source quote.
public enum CoverageCheck {
    /// Passages shorter than this, such as a heading on its own, are not counted.
    public static let minimumWords = 20

    /// The coverage, and the passages no question quotes, for a top-up pass.
    public static func check(questions: [Question], chapterText: String) -> (coverage: ExamCoverage, uncovered: [String]) {
        let passages = PassageIndex.split(chapterText, targetWords: PassageIndex.targetWords)
            .filter { TextTools.words($0).count >= minimumWords }
        let quotes = questions.map { TextTools.words($0.sourceQuote) }.filter { $0.count >= 3 }
        var uncovered: [String] = []
        for passage in passages {
            let text = WordText(passage)
            // A quote can run across two passages, so its first or last four words are enough.
            let quoted = quotes.contains { words in
                text.contains(words.prefix(4).joined(separator: " ")) || text.contains(words.suffix(4).joined(separator: " "))
            }
            if !quoted {
                uncovered.append(passage)
            }
        }
        return (ExamCoverage(passages: passages.count, covered: passages.count - uncovered.count), uncovered)
    }
}
