import XCTest
@testable import GoldfishCore

final class QuoteCheckTests: XCTestCase {
    private let lesson = "Cells are small.\nMitochondria make ATP for the cell."

    func testAcceptsExactSentence() {
        XCTAssertTrue(QuoteCheck.isVerbatim("Mitochondria make ATP for the cell.", in: lesson))
    }

    func testIgnoresCaseSpacingAndSurroundingQuotes() {
        XCTAssertTrue(QuoteCheck.isVerbatim("\"mitochondria  make ATP\"", in: lesson))
        XCTAssertTrue(QuoteCheck.isVerbatim("\u{201C}Mitochondria make ATP for the cell\u{201D}", in: lesson))
    }

    func testRejectsParaphrase() {
        XCTAssertFalse(QuoteCheck.isVerbatim("Mitochondria produce ATP for the cell.", in: lesson))
    }

    func testRejectsTooShortAndEmpty() {
        XCTAssertFalse(QuoteCheck.isVerbatim("make ATP", in: lesson))
        XCTAssertFalse(QuoteCheck.isVerbatim("", in: lesson))
        XCTAssertFalse(QuoteCheck.isVerbatim("anything at all here", in: ""))
    }

    func testRejectsQuotingTheWholeLesson() {
        let longLesson = Array(repeating: "word", count: 40).joined(separator: " ")
        XCTAssertFalse(QuoteCheck.isVerbatim(longLesson, in: longLesson))
    }

    func testRespectsCustomRules() {
        let rules = QuoteRules(minWords: 2, maxWords: 4)
        XCTAssertTrue(QuoteCheck.isVerbatim("make ATP", in: lesson, rules: rules))
        XCTAssertFalse(QuoteCheck.isVerbatim("Mitochondria make ATP for the cell", in: lesson, rules: rules))
    }

    func testKeyTerm() {
        XCTAssertTrue(QuoteCheck.containsKeyTerm("Mitochondria make ATP.", keyTerm: "mitochondri"))
        XCTAssertFalse(QuoteCheck.containsKeyTerm("Cells are small.", keyTerm: "mitochondri"))
        XCTAssertFalse(QuoteCheck.containsKeyTerm("Cells are small.", keyTerm: ""))
    }

    func testNormalizerCollapsesWhitespaceAndStraightensQuotes() {
        XCTAssertEqual(TextNormalizer.normalize("  The  cell\u{2019}s\n ATP "), "the cell's atp")
        XCTAssertEqual(TextNormalizer.cleanQuote("\"Hello there, fish!\""), "hello there, fish")
        XCTAssertEqual(TextNormalizer.wordCount("one two\nthree"), 3)
    }
}
