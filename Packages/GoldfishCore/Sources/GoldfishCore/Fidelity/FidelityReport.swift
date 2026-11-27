import Foundation

/// Turns a Fish Check result into plain text that can be copied off the phone.
public enum FidelityReport {
    public static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    public static func text(
        _ result: FidelityResult,
        meta: FidelityMeta,
        thresholds: FidelityThresholds = FidelityThresholds()
    ) -> String {
        let summary = result.summary
        let rates = summary.rates
        var lines: [String] = []

        // Header
        let dateText = ISO8601DateFormatter().string(from: meta.date)
        let tierParts = summary.tierCounts
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\($0.key.rawValue) \($0.value)" }
        let tierText = tierParts.isEmpty ? "none" : tierParts.joined(separator: ", ")

        lines.append("GOLDFISH FISH CHECK")
        lines.append("Source: \(meta.source)")
        lines.append("Device: \(meta.device)")
        lines.append("Run: \(dateText) | prompt v\(FishPrompt.version) | repeats: \(meta.repeats)")
        lines.append("Trials: \(result.trials.count)/\(result.planned) | errors: \(summary.totalErrors)")
        lines.append("Replies by tier: \(tierText)")
        if let reason = result.stoppedReason {
            lines.append("Note: \(reason)")
        }

        // Verdict
        lines.append("")
        lines.append("VERDICT: \(summary.verdict.title). \(summary.verdict.detail)")

        // Key checks
        let learns = percent(rates.learnsCredited)
        let learnsRaw = percent(rates.learnsRaw)
        let learnsTarget = percent(thresholds.learns)
        let misled = percent(rates.misledCredited)
        let misledRaw = percent(rates.misledRaw)
        let misledTarget = percent(thresholds.misled)
        let overrides = percent(rates.overridesLesson)
        let leakQuote = percent(rates.leakQuoteOnly)
        let leakTarget = percent(thresholds.leak)
        let leakFull = percent(rates.leakFull)
        let leakRaw = percent(rates.leakRaw)
        let gapAbstains = percent(rates.gapAbstains)
        let emptyAbstains = percent(rates.emptyAbstains)
        let emptyLeak = percent(rates.emptyLeakRaw)
        let consistency = summary.consistency.map { percent($0) } ?? "n/a"

        lines.append("")
        lines.append("Key checks")
        lines.append("Learns from a good lesson (credited): \(learns) (needs \(learnsTarget)+), picked correct \(learnsRaw)")
        lines.append("Misled by a wrong lesson (credited): \(misled) (needs \(misledTarget)+), picked planted \(misledRaw), overrode lesson \(overrides)")
        lines.append("Missing fact credited, quote check only: \(leakQuote) (needs \(leakTarget) or less), with keyword check \(leakFull)")
        lines.append("Missing fact answered correctly anyway: \(leakRaw), said not taught \(gapAbstains)")
        lines.append("Empty lesson said not taught: \(emptyAbstains), answered correctly anyway \(emptyLeak)")
        lines.append("Same choice across repeats: \(consistency)")
        lines.append("Latency: p50 \(summary.latencyP50) ms, p90 \(summary.latencyP90) ms, mean \(summary.latencyMean) ms")

        // Counts by lesson type
        lines.append("")
        lines.append("Condition: valid correct planted other abstain quotedOK errors")
        for condition in FidelityCondition.allCases {
            let s = summary.stats[condition] ?? FidelityStats()
            let quoted = "\(s.verbatim)/\(s.answered)"
            lines.append("\(condition.rawValue): \(s.valid) \(s.correct) \(s.planted) \(s.other) \(s.abstain) \(quoted) \(s.errors)")
        }

        // Per question
        let conditionNames = FidelityCondition.allCases.map { $0.rawValue }.joined(separator: " / ")
        lines.append("")
        lines.append("Met expectation by question (\(conditionNames))")
        for item in FidelityDataset.items {
            var cells: [String] = []
            for condition in FidelityCondition.allCases {
                let group = result.trials.filter { $0.itemID == item.id && $0.condition == condition }
                let met = group.filter { $0.asExpected }.count
                cells.append("\(met)/\(group.count)")
            }
            lines.append("\(item.id): \(cells.joined(separator: " / "))")
        }

        // A sample of misses, so the raw replies can be read without a debugger
        let misses = Array(result.trials.filter { !$0.asExpected }.prefix(12))
        if !misses.isEmpty {
            lines.append("")
            lines.append("First misses (question, lesson, pick, reply)")
            for trial in misses {
                let detail = trial.error ?? trial.raw ?? ""
                let flattened = detail
                    .split(whereSeparator: { $0.isNewline })
                    .joined(separator: " | ")
                let shortened = String(flattened.prefix(160))
                lines.append("\(trial.itemID), \(trial.condition.rawValue), \(trial.pick.rawValue): \(shortened)")
            }
        }

        return lines.joined(separator: "\n")
    }
}
