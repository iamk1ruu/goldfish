import XCTest
@testable import GoldfishCore

final class FidelityDatasetTests: XCTestCase {
    private let items = FidelityDataset.items

    func testHasTwentyUniqueQuestions() {
        XCTAssertEqual(items.count, 20)
        XCTAssertEqual(Set(items.map { $0.id }).count, 20)
        XCTAssertEqual(Set(items.map { $0.question }).count, 20)
    }

    func testEveryItemHasFourOptionsAndKeys() {
        for item in items {
            XCTAssertEqual(item.options.count, 4, item.id)
            XCTAssertEqual(item.keys.count, 4, item.id)
            XCTAssertTrue((0..<4).contains(item.correct), item.id)
            XCTAssertTrue((0..<4).contains(item.planted), item.id)
            XCTAssertNotEqual(item.correct, item.planted, item.id)
        }
    }

    func testCorrectAnswersAreBalancedAcrossLetters() {
        for letter in 0..<4 {
            XCTAssertEqual(items.filter { $0.correct == letter }.count, 5, "letter \(letter)")
        }
    }

    func testEachCorrectKeyAppearsOnlyInItsOwnSentence() {
        for item in items {
            let key = item.keys[item.correct]
            for other in items {
                let found = other.sentence.lowercased().contains(key)
                XCTAssertEqual(found, other.id == item.id, "\(key) in \(other.id)")
            }
        }
    }

    func testWrongSentencesCarryThePlantedKeyOnly() {
        for item in items {
            let wrong = item.wrongSentence.lowercased()
            XCTAssertTrue(wrong.contains(item.keys[item.planted]), item.id)
            XCTAssertFalse(wrong.contains(item.keys[item.correct]), item.id)
        }
    }

    func testLessonsAreBuiltForEachCondition() {
        let item = items[3]
        let key = item.keys[item.correct]
        XCTAssertTrue(FidelityLessons.lesson(for: item, condition: .good).lowercased().contains(key))
        XCTAssertFalse(FidelityLessons.lesson(for: item, condition: .gap).lowercased().contains(key))
        XCTAssertFalse(FidelityLessons.lesson(for: item, condition: .wrong).lowercased().contains(key))
        XCTAssertTrue(FidelityLessons.lesson(for: item, condition: .wrong).contains(item.wrongSentence))
        XCTAssertEqual(FidelityLessons.lesson(for: item, condition: .empty), "")

        let gapLines = FidelityLessons.lesson(for: item, condition: .gap).split(separator: "\n")
        XCTAssertEqual(gapLines.count, 19)
    }

    func testPromptRoundTripsLessonAndQuestion() {
        for condition in FidelityCondition.allCases {
            let item = items[7]
            let prompt = FidelityLessons.prompt(for: item, condition: condition)
            let parts = FishPrompt.parts(of: prompt)
            XCTAssertEqual(parts?.question, item.question)
            XCTAssertEqual(parts?.lesson, FidelityLessons.lesson(for: item, condition: condition))
            XCTAssertTrue(prompt.contains("A) \(item.options[0])"))
            XCTAssertTrue(prompt.contains("D) \(item.options[3])"))
        }
    }

    func testPromptFitsTheOnDeviceBudget() {
        // Apple's model allows 4,096 tokens per request. Estimate tokens as words x 1.4.
        let prompt = FidelityLessons.prompt(for: items[0], condition: .good)
        let estimatedTokens = Double(TextNormalizer.wordCount(prompt)) * 1.4
        XCTAssertLessThan(estimatedTokens, 1500)
    }
}

final class FidelityRunnerTests: XCTestCase {
    private func run(_ persona: ScriptedFidelityEngine.Persona, repeats: Int = 1) async -> FidelityResult {
        await FidelityRunner(engine: ScriptedFidelityEngine(persona: persona)).run(repeats: repeats)
    }

    func testPlanCoversEveryQuestionAndConditionForEachRepeat() {
        let plan = FidelityRunner.plan(repeats: 3)
        XCTAssertEqual(plan.count, 240)
        let keys = Set(plan.map { "\($0.item.id):\($0.condition.rawValue):\($0.run)" })
        XCTAssertEqual(keys.count, 240)
    }

    func testPlanOrderIsTheSameEveryTime() {
        let first = FidelityRunner.plan(repeats: 1).map { "\($0.item.id):\($0.condition.rawValue)" }
        let second = FidelityRunner.plan(repeats: 1).map { "\($0.item.id):\($0.condition.rawValue)" }
        XCTAssertEqual(first, second)
    }

    func testIdealFishGetsGo() async {
        let result = await run(.ideal, repeats: 3)
        XCTAssertEqual(result.trials.count, 240)
        XCTAssertEqual(result.summary.verdict.code, .go)
        XCTAssertEqual(result.summary.rates.learnsCredited, 1)
        XCTAssertEqual(result.summary.rates.misledCredited, 1)
        XCTAssertEqual(result.summary.rates.leakQuoteOnly, 0)
        XCTAssertEqual(result.summary.rates.emptyAbstains, 1)
        XCTAssertEqual(result.summary.consistency, 1)
        XCTAssertEqual(result.summary.tierCounts[.scripted], 240)
        XCTAssertTrue(result.trials.allSatisfy { $0.asExpected })
        XCTAssertNil(result.stoppedReason)
    }

    func testFishUsingPriorKnowledgeGetsNoGo() async {
        let result = await run(.leaky)
        XCTAssertEqual(result.summary.verdict.code, .noGo)
        XCTAssertEqual(result.summary.rates.overridesLesson, 1)
        XCTAssertEqual(result.summary.rates.leakRaw, 1)
    }

    func testFishThatParaphrasesGetsNeedsPromptWork() async {
        let result = await run(.sloppy)
        XCTAssertEqual(result.summary.verdict.code, .needsPromptWork)
        XCTAssertEqual(result.summary.rates.learnsRaw, 1)
        XCTAssertEqual(result.summary.rates.learnsCredited, 0)
    }

    func testFishCitingAnUnrelatedSentenceGetsGoWithKeywordCheck() async {
        let result = await run(.gapleak)
        XCTAssertEqual(result.summary.verdict.code, .goWithKeywordCheck)
        XCTAssertEqual(result.summary.rates.leakQuoteOnly, 1)
        XCTAssertEqual(result.summary.rates.leakFull, 0)
    }

    func testFailingFishStopsEarlyAndIsInconclusive() async {
        let result = await run(.broken)
        XCTAssertEqual(result.trials.count, FidelityRunner.maxConsecutiveErrors)
        XCTAssertEqual(result.summary.verdict.code, .inconclusive)
        XCTAssertTrue(result.stoppedReason?.contains("errors in a row") ?? false)
    }

    func testStoppingPartwayReturnsPartialResults() async {
        var asked = 0
        let runner = FidelityRunner(engine: ScriptedFidelityEngine(persona: .ideal))
        let result = await runner.run(
            repeats: 1,
            shouldStop: { asked >= 10 },
            onProgress: { done, _, _ in asked = done }
        )
        XCTAssertEqual(result.trials.count, 10)
        XCTAssertEqual(result.stoppedReason, "Stopped by user.")
        XCTAssertEqual(result.summary.verdict.code, .inconclusive)
    }

    func testReportShowsVerdictAndEveryQuestion() async {
        let result = await run(.ideal)
        let meta = FidelityMeta(source: "test", device: "none", repeats: 1)
        let text = FidelityReport.text(result, meta: meta)
        XCTAssertTrue(text.contains("VERDICT: Go."))
        XCTAssertTrue(text.contains("Replies by tier: scripted 80"))
        for item in FidelityDataset.items {
            XCTAssertTrue(text.contains("\(item.id): 1/1 / 1/1 / 1/1 / 1/1"), item.id)
        }
        XCTAssertFalse(text.contains("First misses"))
    }

    func testReportListsMisses() async {
        let result = await run(.leaky)
        let meta = FidelityMeta(source: "test", device: "none", repeats: 1)
        let text = FidelityReport.text(result, meta: meta)
        XCTAssertTrue(text.contains("VERDICT: No-go as designed."))
        XCTAssertTrue(text.contains("First misses"))
    }

    func testPercentFormatting() {
        XCTAssertEqual(FidelityReport.percent(0), "0%")
        XCTAssertEqual(FidelityReport.percent(0.725), "73%")
        XCTAssertEqual(FidelityReport.percent(1), "100%")
    }
}
