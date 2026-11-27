import SwiftUI
import GoldfishCore

// Loading states. Goldfish shows no spinners.
// Where a wait is drawn says which tier is working: the cloud writes in the sky above the waterline,
// and anything in the water runs on this iPhone.

/// Three purple pixels hopping in turn. Use it wherever a small spinner would go.
struct BubbleDots: View {
    var size: CGFloat = 6

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0, paused: reduceMotion)) { timeline in
            let beat = FinnPainter.step(timeline.date.timeIntervalSinceReferenceDate, 5, 4)
            HStack(spacing: size) {
                ForEach(0..<3, id: \.self) { index in
                    Rectangle()
                        .fill(Theme.brand.opacity(beat == index ? 1 : 0.35))
                        .frame(width: size, height: size)
                        .offset(y: beat == index && !reduceMotion ? -size * 0.7 : 0)
                }
            }
        }
        .frame(height: size * 2, alignment: .bottom)
        .accessibilityElement()
        .accessibilityLabel("Working")
    }
}

/// The long cloud waits: writing the Hidden Exam and the Report Card.
/// The cloud writes above the waterline, pages sink through it, and Finn waits below.
struct CloudWritingView: View {
    /// Shown one after another, three seconds each. The last one stays.
    let captions: [String]
    var tier: FishTier = .cloud
    var height: CGFloat = 210

    @State private var started = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PixelCloudScene(scale: 3)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))

            TimelineView(.periodic(from: started, by: 3.0)) { timeline in
                let step = self.step(at: timeline.date)
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Text(step < captions.count ? captions[step] : "")
                            .font(.poppins(.callout, weight: .medium))
                            .foregroundStyle(Theme.ink)
                        Spacer(minLength: 0)
                        TierBadge(tier: tier)
                    }
                    HStack(spacing: 6) {
                        ForEach(0..<max(captions.count, 1), id: \.self) { index in
                            Capsule()
                                .fill(index < step ? Theme.brand : index == step ? Theme.brand3 : Theme.rule)
                                .frame(height: 6)
                        }
                    }
                    .accessibilityHidden(true)
                }
            }
        }
    }

    private func step(at date: Date) -> Int {
        guard !captions.isEmpty else { return 0 }
        let step = Int(date.timeIntervalSince(started) / 3.0)
        return min(max(step, 0), captions.count - 1)
    }
}

/// Shown for about a second at launch: Finn in a porthole on brand purple, like the Figma splash.
struct SplashView: View {
    @State private var arrived = false

    var body: some View {
        ZStack {
            Theme.banner.ignoresSafeArea()
            VStack(spacing: 26) {
                PixelTank(mood: .happy, scale: 5, fishAt: UnitPoint(x: 0.45, y: 0.55), weeds: [0.04, 0.82], bubbles: 3)
                    .frame(width: 220, height: 220)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Theme.bannerGlow, lineWidth: 8))
                    .scaleEffect(arrived ? 1 : 0.7)
                    .opacity(arrived ? 1 : 0)
                VStack(spacing: 4) {
                    Text("Goldfish")
                        .font(.poppins(size: 40, weight: .bold))
                    Text("Teach the fish. Ace the exam.")
                        .font(.poppins(.body))
                        .opacity(0.75)
                }
                .foregroundStyle(.white)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.7)) {
                arrived = true
            }
        }
    }
}

/// A concept's state as a pixel mark: a dotted ring, a bubble, a pink bubble, then a pearl.
/// Bubbles can pop. Pearls stay.
struct ConceptToken: View {
    let state: ConceptState
    /// About how wide the mark is, in points.
    var size: CGFloat = 18

    var body: some View {
        PixelMark(sprite: ConceptToken.sprite(for: state), scale: max(1, (size / 9).rounded(.down)))
            .frame(width: size, height: size)
    }

    static func sprite(for state: ConceptState) -> PixelSprite {
        switch state {
        case .notTaught: return FinnSprites.notTaught
        case .taught: return FinnSprites.taught
        case .recalled: return FinnSprites.recalled
        case .mastered: return FinnSprites.mastered
        }
    }
}
