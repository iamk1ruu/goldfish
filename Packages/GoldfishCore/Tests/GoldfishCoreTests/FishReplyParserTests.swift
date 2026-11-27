import XCTest
@testable import GoldfishCore

final class FishReplyParserTests: XCTestCase {
    func testCleanReply() {
        let parsed = FishReplyParser.parse("QUOTE: Mitochondria make most of the ATP.\nANSWER: B")
        XCTAssertEqual(parsed, ParsedFishReply(choice: .option(1), quote: "Mitochondria make most of the ATP."))
    }

    func testLowercaseLabelsAndLetter() {
        let parsed = FishReplyParser.parse("quote: the nucleus holds the dna\nanswer: c")
        XCTAssertEqual(parsed?.choice, .option(2))
        XCTAssertEqual(parsed?.quote, "the nucleus holds the dna")
    }

    func testMarkdownDecorationAndOptionText() {
        let parsed = FishReplyParser.parse("**QUOTE:** \"The nucleus is the vault.\"\n**ANSWER:** (B) Nucleus")
        XCTAssertEqual(parsed?.choice, .option(1))
        XCTAssertEqual(TextNormalizer.cleanQuote(parsed?.quote ?? ""), "the nucleus is the vault")
    }

    func testChatterBeforeTheReply() {
        let parsed = FishReplyParser.parse("Sure, here is my reply.\n\nQUOTE: Ribosomes build proteins.\nANSWER: A) Ribosome")
        XCTAssertEqual(parsed?.choice, .option(0))
        XCTAssertEqual(parsed?.quote, "Ribosomes build proteins.")
    }

    func testBothPartsOnOneLine() {
        let parsed = FishReplyParser.parse("QUOTE: Osmosis moves water. ANSWER: C")
        XCTAssertEqual(parsed?.choice, .option(2))
        XCTAssertEqual(parsed?.quote, "Osmosis moves water.")
    }

    func testValueOnTheNextLine() {
        let parsed = FishReplyParser.parse("QUOTE:\nFlagella are tails.\nANSWER:\nD")
        XCTAssertEqual(parsed?.choice, .option(3))
        XCTAssertEqual(parsed?.quote, "Flagella are tails.")
    }

    func testSentenceStyleAnswer() {
        let parsed = FishReplyParser.parse("QUOTE: Plasmids are rings of DNA.\nANSWER: I think it is C.")
        XCTAssertEqual(parsed?.choice, .option(2))
    }

    func testNoneForBoth() {
        let parsed = FishReplyParser.parse("QUOTE: NONE\nANSWER: NONE")
        XCTAssertEqual(parsed, ParsedFishReply(choice: .notTaught, quote: ""))
    }

    func testNoneOfTheAbove() {
        let parsed = FishReplyParser.parse("QUOTE: none\nANSWER: None of the above.")
        XCTAssertEqual(parsed?.choice, .notTaught)
    }

    func testBareNone() {
        XCTAssertEqual(FishReplyParser.parse(" NONE. ")?.choice, .notTaught)
    }

    func testAnswerWithoutQuoteKeepsEmptyQuote() {
        let parsed = FishReplyParser.parse("ANSWER: B")
        XCTAssertEqual(parsed, ParsedFishReply(choice: .option(1), quote: ""))
    }

    func testNoneQuoteWithLetterAnswerHasEmptyQuote() {
        let parsed = FishReplyParser.parse("QUOTE: NONE\nANSWER: A")
        XCTAssertEqual(parsed, ParsedFishReply(choice: .option(0), quote: ""))
    }

    func testRejectsUnreadableReplies() {
        XCTAssertNil(FishReplyParser.parse(""))
        XCTAssertNil(FishReplyParser.parse("I am not sure."))
        XCTAssertNil(FishReplyParser.parse("QUOTE: Something here.\nANSWER: E"))
        XCTAssertNil(FishReplyParser.parse("QUOTE: Something here.\nANSWER: Mitochondrion"))
    }
}
