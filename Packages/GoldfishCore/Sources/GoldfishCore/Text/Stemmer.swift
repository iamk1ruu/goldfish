import Foundation

/// A small suffix stripper for English, so word forms meet at one stem:
/// "diffuses", "diffusing" and "diffusion" all become "diffus", and "swelling" becomes "swell".
///
/// It is not the full Porter algorithm. It handles plurals, "-ed" and "-ing", and the common endings
/// such as "-ation", "-ment" and "-ity", and it leaves words of three letters or fewer alone.
/// Stems are only compared with each other, never shown, so it does not matter that "move" becomes "mov".
/// "-ism", "-ist" and "-er" are kept on purpose: stripping them would join "organ" and "organism",
/// or "live" and "liver".
public enum Stemmer {
    public static func stem(_ word: String) -> String {
        var w = word.lowercased()
        guard w.count > 3, w.allSatisfy({ $0.isLetter }) else { return w }
        w = plural(w)
        w = pastAndProgressive(w)
        // Twice, so "movement" goes to "move" and on to "mov", and "regional" to "region" and "reg".
        for _ in 0..<2 {
            let shorter = derivational(w)
            if shorter == w { break }
            w = shorter
        }
        if w.hasSuffix("e"), w.count >= 4 {
            w.removeLast()
        }
        if w.hasSuffix("y"), w.count > 3 {
            w = String(w.dropLast()) + "i"
        }
        return w
    }

    // MARK: Steps

    private static func plural(_ w: String) -> String {
        if w.hasSuffix("sses") {
            return String(w.dropLast(2))
        }
        if w.hasSuffix("ies"), w.count > 4 {
            return String(w.dropLast(3)) + "i"
        }
        if w.hasSuffix("s"), !w.hasSuffix("ss"), !w.hasSuffix("us"), !w.hasSuffix("is") {
            return String(w.dropLast())
        }
        return w
    }

    private static func pastAndProgressive(_ w: String) -> String {
        var stem: String?
        if w.hasSuffix("ing") {
            stem = String(w.dropLast(3))
        } else if w.hasSuffix("ed"), !w.hasSuffix("eed") {
            stem = String(w.dropLast(2))
        }
        guard let base = stem, base.count >= 3, base.contains(where: isVowel) else { return w }
        // "running" to "run", but "swelling" stays "swell". "concentrated" becomes "concentrate" again.
        let letters = Array(base)
        if let last = letters.last, letters.count >= 2, letters[letters.count - 2] == last,
           !isVowel(last), !"lsz".contains(last) {
            return String(base.dropLast())
        }
        if base.hasSuffix("at") || base.hasSuffix("bl") || base.hasSuffix("iz") {
            return base + "e"
        }
        return base
    }

    /// Endings and the shortest stem each may leave, longest ending first.
    private static let endings: [(suffix: String, minStem: Int)] = [
        ("ational", 3), ("ization", 3), ("ation", 3), ("ition", 3), ("ment", 3), ("ness", 3),
        ("able", 3), ("ible", 3), ("ance", 3), ("ence", 3),
        ("ion", 3), ("ity", 3), ("ive", 3), ("ous", 3), ("ful", 3), ("ize", 3), ("ise", 3), ("ate", 3),
        ("al", 5), ("ly", 4), ("ic", 4),
    ]

    private static func derivational(_ w: String) -> String {
        for (suffix, minStem) in endings where w.hasSuffix(suffix) {
            let base = String(w.dropLast(suffix.count))
            if base.count >= minStem && base.contains(where: isVowel) {
                return base
            }
        }
        return w
    }

    private static func isVowel(_ character: Character) -> Bool {
        "aeiouy".contains(character)
    }
}
