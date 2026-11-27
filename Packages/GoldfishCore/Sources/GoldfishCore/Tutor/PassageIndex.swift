import Foundation

/// A short piece of a chapter that Orla can point to. Its text is copied from the chapter, never written by a model.
public struct Passage: Equatable, Identifiable, Sendable {
    /// "chapterID#number".
    public let id: String
    public let chapterID: String
    public let chapterTitle: String
    /// 1-based, in chapter order.
    public let number: Int
    public let text: String

    public init(chapterID: String, chapterTitle: String, number: Int, text: String) {
        self.id = "\(chapterID)#\(number)"
        self.chapterID = chapterID
        self.chapterTitle = chapterTitle
        self.number = number
        self.text = text
    }
}

/// Turns a sentence into a vector whose direction stands for its meaning, so two sentences that
/// say the same thing in different words point the same way. The app supplies Apple's built-in sentence
/// embedding (NaturalLanguage), which runs on the iPhone with no model call. Tests supply a fake.
public protocol SentenceEmbedder {
    /// Nil when the text cannot be embedded.
    func vector(for text: String) -> [Double]?
}

/// One passage the search found, and how.
public struct PassageHit: Equatable, Sendable {
    public let passage: Passage
    /// The question shares a word, or a word's stem, with the passage.
    public let matchedWords: Bool
    /// A sentence of the passage means about the same as the question.
    public let matchedMeaning: Bool
    /// The best cosine similarity between the question and one of the passage's sentences.
    /// Nil when meaning was not searched.
    public let similarity: Double?
}

/// What the search found for one question.
public struct PassageSearch: Equatable, Sendable {
    public let hits: [PassageHit]
    /// The question was a short follow-up, so it was searched together with the one before it.
    public let followUp: Bool
    /// Meaning was searched as well as words.
    public let searchedMeaning: Bool
    /// The highest similarity any passage reached. Diagnostics logs it, so the floor can be tuned on the phone.
    public let bestSimilarity: Double?

    public var passages: [Passage] {
        hits.map(\.passage)
    }

    public static let empty = PassageSearch(hits: [], followUp: false, searchedMeaning: false, bestSimilarity: nil)
}

/// The search behind Orla, the tutor. Chapters are cut into short passages along sentence
/// boundaries. A question is searched two ways, and the two rankings are joined:
///
/// - **By its words**, with BM25. Words count by their stem, so "swell" finds "swelling", and a word that
///   also matches exactly scores a little more, so the chapter's own wording wins a tie.
/// - **By its meaning**, when the app has given the index a sentence embedding. "How does a fish breathe?"
///   then finds "oxygen is pulled out of water by the gills" with no word in common.
///
/// The rankings are joined by reciprocal rank fusion, so a passage both searches agree on comes first.
/// Neither search calls a model, so this always runs on the iPhone, offline.
public struct PassageIndex: Sendable {
    public let passages: [Passage]
    private let wordCounts: [[String: Int]]
    private let stemCounts: [[String: Int]]
    private let lengths: [Int]
    private let wordFrequency: [String: Int]
    private let stemFrequency: [String: Int]
    private let averageLength: Double
    /// Unit vectors for each sentence of each passage, once `embedded(with:)` has run.
    private var sentenceVectors: [[[Double]]] = []

    /// About how many words a passage holds. Three of them fit Apple's on-device context with room to spare.
    public static let targetWords = 90
    /// What an exact word match adds on top of its stem match.
    public static let exactWeight = 0.5
    /// How much the previous question's words count when a short follow-up is searched with it.
    public static let previousWeight = 0.5
    /// Below this cosine similarity a sentence does not count as meaning the same as the question.
    /// A starting value, not measured: Remote Config `tutor_meaning_floor` changes it.
    public static let defaultMeaningFloor = 0.5
    /// How many passages from each ranking take part in the join.
    static let fusionDepth = 10
    /// The usual constant for reciprocal rank fusion.
    static let fusionK = 60.0

    public init(chapters: [Chapter], targetWords: Int = PassageIndex.targetWords) {
        var passages: [Passage] = []
        for chapter in chapters {
            for (offset, text) in PassageIndex.split(chapter.sourceText, targetWords: targetWords).enumerated() {
                passages.append(Passage(chapterID: chapter.id, chapterTitle: chapter.title, number: offset + 1, text: text))
            }
        }
        self.passages = passages
        var words: [[String: Int]] = []
        var stems: [[String: Int]] = []
        var lengths: [Int] = []
        var wordFrequency: [String: Int] = [:]
        var stemFrequency: [String: Int] = [:]
        for passage in passages {
            let terms = PassageIndex.terms(passage.text)
            var wordCount: [String: Int] = [:]
            var stemCount: [String: Int] = [:]
            for term in terms {
                wordCount[term, default: 0] += 1
                stemCount[Stemmer.stem(term), default: 0] += 1
            }
            for term in wordCount.keys {
                wordFrequency[term, default: 0] += 1
            }
            for stem in stemCount.keys {
                stemFrequency[stem, default: 0] += 1
            }
            words.append(wordCount)
            stems.append(stemCount)
            lengths.append(terms.count)
        }
        wordCounts = words
        stemCounts = stems
        self.lengths = lengths
        self.wordFrequency = wordFrequency
        self.stemFrequency = stemFrequency
        averageLength = lengths.isEmpty ? 1 : max(1, Double(lengths.reduce(0, +)) / Double(lengths.count))
    }

    /// True once the passages have been embedded, so meaning can be searched.
    public var searchesMeaning: Bool {
        !sentenceVectors.isEmpty
    }

    /// A copy whose passages are embedded sentence by sentence, so `find` can also search by meaning.
    /// If nothing can be embedded (no embedding on this phone), the copy searches words only.
    public func embedded(with embedder: SentenceEmbedder) -> PassageIndex {
        var copy = self
        copy.sentenceVectors = passages.map { passage in
            TextTools.sentences(passage.text).compactMap { sentence in
                embedder.vector(for: sentence).flatMap(PassageIndex.unit)
            }
        }
        if copy.sentenceVectors.allSatisfy({ $0.isEmpty }) {
            copy.sentenceVectors = []
        }
        return copy
    }

    /// The passage that holds a quote from the chapter, such as a question's `sourceQuote`, or
    /// failing that the passage that best matches the quote's words.
    public func passage(holding quote: String) -> Passage? {
        let clean = quote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        return passages.first { TextTools.containsWords($0.text, clean) } ?? search(clean, limit: 1).first
    }

    /// The passages that best match a question by its words, best first. Passages that share no word
    /// or stem with it are left out.
    public func search(_ question: String, limit: Int = 3) -> [Passage] {
        find(question, limit: limit).passages
    }

    /// Searches by words and, when an embedder is given and the passages are embedded, by meaning.
    /// A short follow-up such as "Why doesn't it swell up?" is searched together with `previous`.
    public func find(
        _ question: String,
        previous: String? = nil,
        embedder: SentenceEmbedder? = nil,
        meaningFloor: Double = PassageIndex.defaultMeaningFloor,
        limit: Int = 3
    ) -> PassageSearch {
        let earlier = previous?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let followUp = !earlier.isEmpty && TutorFollowUp.isFollowUp(question)

        // By words. The new question's words count fully, the earlier question's at half weight.
        var weights: [String: Double] = [:]
        if followUp {
            for term in PassageIndex.terms(earlier) {
                weights[term] = PassageIndex.previousWeight
            }
        }
        for term in PassageIndex.terms(question) {
            weights[term] = 1
        }
        let wordScores = lexicalScores(weights)

        // By meaning: the best match between the question and any one sentence of a passage.
        var similarities: [Double]?
        if let embedder = embedder, !sentenceVectors.isEmpty {
            var queries = [question]
            if followUp {
                queries.append(earlier + " " + question)
            }
            let vectors = queries.compactMap { embedder.vector(for: $0).flatMap(PassageIndex.unit) }
            if !vectors.isEmpty {
                similarities = sentenceVectors.map { sentences in
                    var best = -1.0
                    for sentence in sentences {
                        for query in vectors {
                            best = max(best, PassageIndex.dot(sentence, query))
                        }
                    }
                    return best
                }
            }
        }

        let byWords = passages.indices
            .filter { wordScores[$0] > 0 }
            .sorted { wordScores[$0] != wordScores[$1] ? wordScores[$0] > wordScores[$1] : $0 < $1 }
        let byMeaning = similarities.map { values in
            values.indices
                .filter { values[$0] >= meaningFloor }
                .sorted { values[$0] != values[$1] ? values[$0] > values[$1] : $0 < $1 }
        } ?? []

        // Reciprocal rank fusion: each ranking adds 1 / (k + rank).
        var fused: [Int: Double] = [:]
        for (rank, index) in byWords.prefix(PassageIndex.fusionDepth).enumerated() {
            fused[index, default: 0] += 1 / (PassageIndex.fusionK + Double(rank + 1))
        }
        for (rank, index) in byMeaning.prefix(PassageIndex.fusionDepth).enumerated() {
            fused[index, default: 0] += 1 / (PassageIndex.fusionK + Double(rank + 1))
        }
        let order = fused.keys.sorted { a, b in
            let fa = fused[a] ?? 0
            let fb = fused[b] ?? 0
            if fa != fb { return fa > fb }
            if wordScores[a] != wordScores[b] { return wordScores[a] > wordScores[b] }
            return a < b
        }
        let hits = order.prefix(limit).map { index in
            PassageHit(
                passage: passages[index],
                matchedWords: wordScores[index] > 0,
                matchedMeaning: (similarities?[index] ?? -1) >= meaningFloor,
                similarity: similarities?[index]
            )
        }
        return PassageSearch(
            hits: hits, followUp: followUp, searchedMeaning: similarities != nil,
            bestSimilarity: similarities?.max()
        )
    }

    // MARK: Scoring

    /// BM25 on stems, plus a smaller BM25 on exact words.
    private func lexicalScores(_ weights: [String: Double]) -> [Double] {
        guard !weights.isEmpty else { return Array(repeating: 0, count: passages.count) }
        var stemWeights: [String: Double] = [:]
        for (term, weight) in weights {
            let stem = Stemmer.stem(term)
            stemWeights[stem] = max(stemWeights[stem] ?? 0, weight)
        }
        return passages.indices.map { index in
            let length = Double(lengths[index])
            return bm25(stemWeights, counts: stemCounts[index], frequency: stemFrequency, length: length)
                + PassageIndex.exactWeight * bm25(weights, counts: wordCounts[index], frequency: wordFrequency, length: length)
        }
    }

    private func bm25(_ query: [String: Double], counts: [String: Int], frequency: [String: Int], length: Double) -> Double {
        let k1 = 1.2
        let b = 0.75
        let total = Double(passages.count)
        var score = 0.0
        // Sorted, so the sum is added up in the same order every time.
        for term in query.keys.sorted() {
            guard let tf = counts[term], let weight = query[term] else { continue }
            let df = Double(frequency[term] ?? 0)
            let idf = log(1 + (total - df + 0.5) / (df + 0.5))
            score += weight * idf * Double(tf) * (k1 + 1) / (Double(tf) + k1 * (1 - b + b * length / averageLength))
        }
        return score
    }

    static func unit(_ vector: [Double]) -> [Double]? {
        let length = vector.reduce(0) { $0 + $1 * $1 }.squareRoot()
        guard length > 0, length.isFinite else { return nil }
        return vector.map { $0 / length }
    }

    static func dot(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count else { return -1 }
        var sum = 0.0
        for index in a.indices {
            sum += a[index] * b[index]
        }
        return sum
    }

    // MARK: Passages and terms

    /// Cuts text into passages of about `targetWords`, never splitting a sentence.
    /// A section heading (a short line with no end punctuation) always starts a new passage,
    /// and a short leftover at the end of a section joins the passage before it.
    static func split(_ text: String, targetWords: Int) -> [String] {
        var passages: [(text: [String], words: Int, startsSection: Bool)] = []
        var current: [String] = []
        var words = 0
        var startsSection = true
        func flush() {
            if !current.isEmpty {
                passages.append((current, words, startsSection))
            }
            current = []
            words = 0
        }
        for sentence in TextTools.sentences(text) {
            let count = TextTools.words(sentence).count
            let heading = isHeading(sentence, wordCount: count)
            if words > 0 && (heading || words + count > targetWords) {
                flush()
                startsSection = heading
            }
            current.append(sentence)
            if !heading {
                words += count
            }
        }
        flush()
        // Fold short leftovers into the passage before, so a section is not cut into a stub.
        var merged: [(text: [String], words: Int, startsSection: Bool)] = []
        for passage in passages {
            if let last = merged.last, !passage.startsSection, passage.words < targetWords / 3 {
                merged[merged.count - 1] = (last.text + passage.text, last.words + passage.words, last.startsSection)
            } else {
                merged.append(passage)
            }
        }
        return merged.map { $0.text.joined(separator: " ") }
    }

    /// A short line with no end punctuation, such as "The swim bladder".
    static func isHeading(_ sentence: String, wordCount: Int) -> Bool {
        guard wordCount > 0, wordCount <= 8, let last = sentence.trimmingCharacters(in: .whitespaces).last else { return false }
        return !".!?:;\"'\u{201D})".contains(last)
    }

    /// The words that carry meaning: lowercase, with common words removed.
    static func terms(_ text: String) -> [String] {
        TextTools.words(text).filter { $0.count > 1 && !stopWords.contains($0) }
    }

    static let stopWords: Set<String> = [
        "the", "a", "an", "of", "to", "in", "on", "at", "by", "for", "with", "from", "into", "about", "as",
        "is", "are", "was", "were", "be", "been", "being", "am", "do", "does", "did", "done", "has", "have", "had",
        "and", "or", "but", "if", "then", "than", "so", "not", "no", "yes",
        "it", "its", "this", "that", "these", "those", "there", "their", "they", "them", "he", "she", "his", "her",
        "i", "me", "my", "we", "our", "you", "your", "what", "why", "how", "which", "who", "whom", "when", "where",
        "can", "could", "will", "would", "should", "may", "might", "must", "just", "also", "very", "more", "most",
        "some", "any", "all", "each", "one", "only", "own", "same", "such", "too", "up", "out", "over", "under",
        "again", "once", "here", "both", "few", "other", "while", "because", "until", "during", "through",
        "explain", "mean", "means", "tell", "please",
        // What is left of a contraction once the apostrophe splits it: "doesn't" is "doesn" and "t".
        "doesn", "don", "didn", "isn", "aren", "wasn", "weren", "won", "wouldn", "couldn", "shouldn",
        "hasn", "haven", "hadn", "ll", "ve", "re",
    ]
}

/// Tells a follow-up ("Why doesn't it swell up?", "Why?", "What about plants?") from a new question.
/// A follow-up is searched together with the question before it, because on its own it names nothing to find.
public enum TutorFollowUp {
    /// Words that point back at something already said.
    static let pointers: Set<String> = ["it", "its", "that", "this", "they", "them", "those", "these", "there", "he", "she", "one", "ones"]
    static let openers: Set<String> = ["why", "how", "and", "but", "so", "then"]

    public static func isFollowUp(_ question: String) -> Bool {
        let words = TextTools.words(question)
        guard let first = words.first else { return false }
        let content = PassageIndex.terms(question)
        if content.isEmpty {
            return true
        }
        if content.count <= 3 && words.contains(where: { pointers.contains($0) }) {
            return true
        }
        if content.count <= 1 && openers.contains(first) && words.count <= 4 {
            return true
        }
        return words.count >= 2 && first == "what" && words[1] == "about" && content.count <= 2
    }
}
