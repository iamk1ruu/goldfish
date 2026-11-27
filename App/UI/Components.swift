import SwiftUI
import GoldfishCore

/// Where an answer ran. A pixel phone for this iPhone, a pixel cloud for the cloud.
struct TierBadge: View {
    let tier: FishTier
    var cached = false

    var body: some View {
        Pill(
            text: cached ? "Remembered" : tier.label,
            tint: cached ? Theme.gapTint : Theme.tint(for: tier),
            mark: cached ? nil : mark,
            systemImage: cached ? "arrow.uturn.backward" : (tier == .scripted ? "theatermasks" : nil)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cached ? "Answer reused from an unchanged lesson" : "Ran \(tier.label)")
    }

    private var mark: PixelSprite? {
        switch tier {
        case .onDevice: return FinnSprites.phone
        case .cloud: return FinnSprites.cloudIcon
        case .scripted: return nil
        }
    }
}

struct VerdictChip: View {
    let verdict: FishVerdict

    var body: some View {
        Pill(text: verdict.label, tint: Theme.tint(for: verdict))
    }
}

struct StateChip: View {
    let state: ConceptState

    var body: some View {
        Pill(text: state.label, tint: Theme.tint(for: state))
    }
}

/// "8 on this iPhone, 0 cloud", plus whether the phone is offline.
struct HybridMeter: View {
    let answers: [FishAnswer]
    let isOnline: Bool

    var body: some View {
        let onDevice = answers.filter { $0.tier == .onDevice && !$0.cached }.count
        let cloud = answers.filter { $0.tier == .cloud && !$0.cached }.count
        let scripted = answers.filter { $0.tier == .scripted && !$0.cached }.count
        let remembered = answers.filter { $0.cached }.count
        HStack(spacing: 12) {
            HStack(spacing: 5) {
                PixelMark(sprite: FinnSprites.phone, scale: 1)
                Text("\(onDevice) on this iPhone")
            }
            .foregroundStyle(Theme.onDevice)
            HStack(spacing: 5) {
                PixelMark(sprite: FinnSprites.cloudIcon, scale: 1)
                Text("\(cloud) cloud")
            }
            .foregroundStyle(Theme.cloud)
            if scripted > 0 {
                Label("\(scripted) scripted", systemImage: "theatermasks")
                    .foregroundStyle(Theme.ink3)
            }
            if remembered > 0 {
                Label("\(remembered) remembered", systemImage: "arrow.uturn.backward")
                    .foregroundStyle(Theme.ink3)
            }
            Spacer(minLength: 0)
            if !isOnline {
                Label("Offline", systemImage: "airplane")
                    .foregroundStyle(Theme.mixUpTint.text)
            }
        }
        .font(.poppins(.caption, weight: .semibold))
        .labelStyle(.titleAndIcon)
        .accessibilityElement(children: .combine)
    }
}

/// The text of one lesson section with the sentence the fish quoted lit up.
/// Put it on paper with `.paperStyle()`.
struct HighlightedText: View {
    let text: String
    let highlight: String?

    var body: some View {
        Text(attributed)
            .font(.poppins(.callout))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var attributed: AttributedString {
        var result = AttributedString(text)
        if let highlight = highlight, !highlight.isEmpty, let range = result.range(of: highlight) {
            result[range].backgroundColor = Theme.highlight
            result[range].foregroundColor = Theme.highlightInk
            result[range].font = .poppins(.callout, weight: .medium)
        }
        return result
    }
}

/// Empty and error states with the fish.
struct FishMessage: View {
    let title: String
    let message: String
    var mood: FishMood = .confused

    var body: some View {
        VStack(spacing: 12) {
            FishView(mood: mood, size: 90)
            Text(title)
                .font(.poppins(.title3))
                .foregroundStyle(Theme.ink)
            Text(message)
                .font(.poppins(.callout))
                .foregroundStyle(Theme.ink2)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}
