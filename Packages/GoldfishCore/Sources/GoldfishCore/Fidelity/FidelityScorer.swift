import Foundation

/// Builds the lessons and prompts for the Fish Check.
public enum FidelityLessons {
    public static func lesson(
        for item: FidelityItem,
        condition: FidelityCondition,
        items: [FidelityItem] = FidelityDataset.items
    ) -> String {
        switch condition {
        case .good:
            return items.map { $0.sentence }.joined(separator: "\n")
        case .gap:
            return items.filter { $0.id != item.id }.map { $0.sentence }.joined(separator: "\n")
        case .wrong:
            return items.map { $0.id == item.id ? $0.wrongSentence : $0.sentence }.joined(separator: "\n")
        case .empty:
            return ""
        }
    }

    public static func prompt(for item: FidelityItem, condition: FidelityCondition) -> String {
        FishPrompt.build(
            lesson: lesson(for: item, condition: condition),
            question: item.question,
            options: item.options
        )
    }
}

/// Grades Fish Check trials and turns them into a verdict.
public enum FidelityScorer {
    public static func grade(
        item: FidelityItem,
        condition: FidelityCondition,
        run: Int,
        reply: FishReply?,
        error: String?,
        latencyMs: Int
    ) -> FidelityTrial {
        guard let reply = reply, error == nil else {
            return FidelityTrial(
                itemID: item.id, condition: condition, run: run, latencyMs: latencyMs,
                raw: reply?.text, error: error ?? "No reply", pick: .error, quote: "",
                verbatim: false, keyed: false, asExpected: false, tier: reply?.tier
            )
        }
        guard let parsed = FishReplyParser.parse(reply.text, optionCount: item.options.count) else {
            return FidelityTrial(
                itemID: item.id, condition: condition, run: run, latencyMs: latencyMs,
                raw: reply.text, error: nil, pick: .invalid, quote: "",
                verbatim: false, keyed: false, asExpected: false, tier: reply.tier
            )
        }

        var pick = FidelityPick.abstain
        var verbatim = false
        var keyed = false

        if case .option(let index) = parsed.choice {
            if index == item.correct {
                pick = .correct
            } else if index == item.planted {
                pick = .planted
            } else {
                pick = .other
            }
            let lesson = FidelityLessons.lesson(for: item, condition: condition)
            verbatim = QuoteCheck.isVerbatim(parsed.quote, in: lesson)
            if index < item.keys.count {
                keyed = QuoteCheck.containsKeyTerm(parsed.quote, keyTerm: item.keys[index])
            }
        }

        let creditable = verbatim && keyed
        let asExpected: Bool
        switch condition {
        case .good:
            asExpected = pick == .correct && creditable
        case .wrong:
            asExpected = pick == .planted && creditable
        case .gap, .empty:
            asExpected = pick == .abstain
        }

        return FidelityTrial(
            itemID: item.id, condition: condition, run: run, latencyMs: latencyMs,
            raw: reply.text, error: nil, pick: pick, quote: parsed.quote,
            verbatim: verbatim, keyed: keyed, asExpected: asExpected, tier: reply.tier
        )
    }

    public static func summarize(
        _ trials: [FidelityTrial],
        thresholds: FidelityThresholds = FidelityThresholds()
    ) -> FidelitySummary {
        var stats: [FidelityCondition: FidelityStats] = [:]
        for condition in FidelityCondition.allCases {
            stats[condition] = FidelityStats()
        }
        var groups: [String: [FidelityPick]] = [:]
        var latencies: [Int] = []
        var tierCounts: [FishTier: Int] = [:]

        for trial in trials {
            if let tier = trial.tier {
                tierCounts[tier, default: 0] += 1
            }
            var entry = stats[trial.condition] ?? FidelityStats()
            entry.total += 1

            if trial.pick == .error || trial.pick == .invalid {
                entry.errors += 1
                stats[trial.condition] = entry
                continue
            }

            entry.valid += 1
            latencies.append(trial.latencyMs)
            switch trial.pick {
            case .correct: entry.correct += 1
            case .planted: entry.planted += 1
            case .other: entry.other += 1
            case .abstain: entry.abstain += 1
            case .invalid, .error: break
            }
            if trial.pick != .abstain {
                entry.answered += 1
                if trial.verbatim {
                    entry.verbatim += 1
                }
            }
            if trial.pick == .correct && trial.verbatim {
                entry.creditedQuote += 1
                if trial.keyed {
                    entry.creditedFull += 1
                }
            }
            if trial.pick == .planted && trial.verbatim && trial.keyed {
                entry.followed += 1
            }
            stats[trial.condition] = entry
            groups["\(trial.condition.rawValue):\(trial.itemID)", default: []].append(trial.pick)
        }

        let good = stats[.good] ?? FidelityStats()
        let gap = stats[.gap] ?? FidelityStats()
        let wrong = stats[.wrong] ?? FidelityStats()
        let empty = stats[.empty] ?? FidelityStats()

        var rates = FidelityRates()
        rates.learnsRaw = ratio(good.correct, good.valid)
        rates.learnsCredited = ratio(good.creditedFull, good.valid)
        rates.misledRaw = ratio(wrong.planted, wrong.valid)
        rates.misledCredited = ratio(wrong.followed, wrong.valid)
        rates.overridesLesson = ratio(wrong.correct, wrong.valid)
        rates.leakRaw = ratio(gap.correct, gap.valid)
        rates.leakQuoteOnly = ratio(gap.creditedQuote, gap.valid)
        rates.leakFull = ratio(gap.creditedFull, gap.valid)
        rates.gapAbstains = ratio(gap.abstain, gap.valid)
        rates.emptyAbstains = ratio(empty.abstain, empty.valid)
        rates.emptyLeakRaw = ratio(empty.correct, empty.valid)

        let repeated = groups.values.filter { $0.count > 1 }
        let stable = repeated.filter { picks in picks.allSatisfy { $0 == picks[0] } }.count
        let consistency: Double? = repeated.isEmpty ? nil : Double(stable) / Double(repeated.count)

        let sorted = latencies.sorted()
        let mean = sorted.isEmpty ? 0 : sorted.reduce(0, +) / sorted.count
        let totalErrors = FidelityCondition.allCases.reduce(0) { $0 + (stats[$1]?.errors ?? 0) }
        let errorRate = ratio(totalErrors, trials.count)

        let verdict = decideVerdict(rates: rates, stats: stats, errorRate: errorRate, thresholds: thresholds)

        return FidelitySummary(
            stats: stats,
            rates: rates,
            totalErrors: totalErrors,
            errorRate: errorRate,
            consistency: consistency,
            latencyP50: percentile(sorted, 50),
            latencyP90: percentile(sorted, 90),
            latencyMean: mean,
            tierCounts: tierCounts,
            verdict: verdict
        )
    }

    static func decideVerdict(
        rates: FidelityRates,
        stats: [FidelityCondition: FidelityStats],
        errorRate: Double,
        thresholds: FidelityThresholds
    ) -> FidelityVerdict {
        let tooFewValid = FidelityCondition.allCases.contains { (stats[$0]?.valid ?? 0) < thresholds.minValid }
        if tooFewValid || errorRate > thresholds.maxErrorRate {
            return FidelityVerdict(
                code: .inconclusive,
                title: "Inconclusive",
                detail: "There are too few valid results to decide. Run the full check again."
            )
        }

        if rates.learnsRaw < thresholds.learns || rates.misledRaw < thresholds.misled {
            var reasons: [String] = []
            if rates.learnsRaw < thresholds.learns {
                reasons.append("it often misses facts that a good lesson teaches")
            }
            if rates.misledRaw < thresholds.misled {
                reasons.append("it often overrides a wrong lesson with what it already knows")
            }
            return FidelityVerdict(
                code: .noGo,
                title: "No-go as designed",
                detail: "The model does not reliably follow the lesson: "
                    + reasons.joined(separator: ", and ")
                    + ". The core loop would feel unfair."
            )
        }

        if rates.learnsCredited < thresholds.learns || rates.misledCredited < thresholds.misled {
            return FidelityVerdict(
                code: .needsPromptWork,
                title: "Needs prompt work",
                detail: "The model picks the answers the lesson supports, but its quotes fail the checks. "
                    + "Try the two-step fish before deciding."
            )
        }

        if rates.leakQuoteOnly > thresholds.leak {
            return FidelityVerdict(
                code: .goWithKeywordCheck,
                title: "Go, with the keyword check",
                detail: "The model learns from lessons, but it can get past the word-for-word check "
                    + "when a fact is missing. Goldfish must keep the keyword check."
            )
        }

        return FidelityVerdict(
            code: .go,
            title: "Go",
            detail: "The model sticks to the lesson, and the word-for-word quote check is enough to protect the core loop."
        )
    }

    static func ratio(_ part: Int, _ whole: Int) -> Double {
        whole == 0 ? 0 : Double(part) / Double(whole)
    }

    static func percentile(_ sorted: [Int], _ p: Int) -> Int {
        guard !sorted.isEmpty else { return 0 }
        let rank = Int((Double(p) / 100.0 * Double(sorted.count)).rounded(.up)) - 1
        return sorted[min(sorted.count - 1, max(0, rank))]
    }
}
