import Foundation

/// How long "Show me where to look" waits before offering "Put it away and teach Finn".
///
/// The pause is there so the student reads the whole part of the chapter, not only the line that answers
/// the question, before closing it and explaining it from memory. It is set at
/// about four words a second, an unhurried reading pace, and kept between 6 and 20 seconds so a short
/// passage is not rushed and a long one is not a chore. A starting value, not a measured one.
public enum ReadingPause {
    public static let wordsPerSecond = 4.0
    public static let shortest = 6.0
    public static let longest = 20.0

    public static func seconds(for text: String) -> Double {
        let words = Double(TextTools.words(text).count)
        return min(longest, max(shortest, words / wordsPerSecond))
    }
}
