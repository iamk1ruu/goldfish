import Foundation

/// One planned prompt in a Fish Check run.
public struct FidelityPlanEntry {
    public let item: FidelityItem
    public let condition: FidelityCondition
    public let run: Int
}

/// A small seeded generator so every run asks questions in the same shuffled order.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        var z = state
        z ^= z >> 33
        z = z &* 0xff51afd7ed558ccd
        z ^= z >> 33
        return z
    }
}

/// Runs the Fish Check against any fish engine and returns graded results.
public struct FidelityRunner {
    public static let maxConsecutiveErrors = 5

    private let engine: FishEngine

    public init(engine: FishEngine) {
        self.engine = engine
    }

    /// Every question with every lesson, repeated, in a fixed shuffled order.
    /// Shuffling spreads the conditions across the run, so heat or slowdowns
    /// do not fall on one condition.
    public static func plan(repeats: Int) -> [FidelityPlanEntry] {
        var entries: [FidelityPlanEntry] = []
        for run in 1...max(1, repeats) {
            for condition in FidelityCondition.allCases {
                for item in FidelityDataset.items {
                    entries.append(FidelityPlanEntry(item: item, condition: condition, run: run))
                }
            }
        }
        var generator = SeededGenerator(seed: 20261113)
        entries.shuffle(using: &generator)
        return entries
    }

    public func run(
        repeats: Int = 2,
        shouldStop: @escaping () -> Bool = { false },
        onProgress: @escaping (_ done: Int, _ total: Int, _ trial: FidelityTrial) -> Void = { _, _, _ in }
    ) async -> FidelityResult {
        let plan = FidelityRunner.plan(repeats: repeats)
        var trials: [FidelityTrial] = []
        var consecutiveErrors = 0
        var stoppedReason: String? = nil

        for (index, entry) in plan.enumerated() {
            if shouldStop() {
                stoppedReason = "Stopped by user."
                break
            }

            let prompt = FidelityLessons.prompt(for: entry.item, condition: entry.condition)
            let started = Date()
            var reply: FishReply? = nil
            var errorText: String? = nil
            do {
                reply = try await engine.reply(to: prompt)
            } catch {
                errorText = String(describing: error)
            }
            let latencyMs = Int(Date().timeIntervalSince(started) * 1000)

            let trial = FidelityScorer.grade(
                item: entry.item,
                condition: entry.condition,
                run: entry.run,
                reply: reply,
                error: errorText,
                latencyMs: latencyMs
            )
            trials.append(trial)
            onProgress(index + 1, plan.count, trial)

            if let errorText = errorText {
                consecutiveErrors += 1
                if consecutiveErrors >= FidelityRunner.maxConsecutiveErrors {
                    stoppedReason = "Stopped after \(FidelityRunner.maxConsecutiveErrors) errors in a row. Last error: \(errorText)"
                    break
                }
            } else {
                consecutiveErrors = 0
            }
        }

        return FidelityResult(
            trials: trials,
            planned: plan.count,
            stoppedReason: stoppedReason,
            summary: FidelityScorer.summarize(trials)
        )
    }
}
