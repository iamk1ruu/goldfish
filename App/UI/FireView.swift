import SwiftUI
import GoldfishCore

/// The 8-bit fire. It flickers while lit, glows as embers after a missed day, and smokes when out.
/// The pixels are FIRE in tools/art/finn8.js.
struct PixelFire: View {
    let flame: FireStreak.Flame
    /// Points per pixel.
    var scale: CGFloat = 2

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let burning = flame == .lit || flame == .waiting
        TimelineView(.animation(minimumInterval: 1.0 / 6.0, paused: reduceMotion || !burning)) { timeline in
            Canvas { context, _ in
                PixelPen(context: context, scale: scale)
                    .sprite(sprite(time: timeline.date.timeIntervalSinceReferenceDate), x: 1, y: 1)
            }
        }
        .frame(width: CGFloat(FinnSprites.fireOut.width) * scale, height: CGFloat(FinnSprites.fireOut.height) * scale)
        .accessibilityHidden(true)
    }

    private func sprite(time: Double) -> PixelSprite {
        switch flame {
        case .lit, .waiting:
            let frame = reduceMotion ? 0 : FinnPainter.step(time, 6, FinnSprites.fireLit.count)
            return FinnSprites.fireLit[frame]
        case .embers:
            return FinnSprites.fireEmbers
        case .out:
            return FinnSprites.fireOut
        }
    }
}

extension FireStreak {
    /// One line for Today, in the fire's own voice. It never shows a zero.
    var message: String {
        switch flame {
        case .lit: return "Lit today. Keep it going tomorrow."
        case .waiting: return "Teach today to keep it growing."
        case .embers: return "Embers! Teach today and your \(days) days stay."
        case .out: return best > 0 ? "Teach today to light a new fire. Your best was \(best) days." : "Teach today to light your first fire."
        }
    }

    var title: String {
        flame == .out ? "Fire's out" : "\(days)-day fire"
    }

    var spoken: String {
        switch flame {
        case .lit: return "Fire lit: \(days) teaching days. Best \(best)."
        case .waiting: return "Fire burning: \(days) teaching days. Teach today to keep it growing."
        case .embers: return "Fire down to embers: \(days) teaching days. Teach today to keep them."
        case .out: return "Fire out. Best \(best) teaching days."
        }
    }
}

/// The fire and its count, small, for the top of Today.
struct FireBadge: View {
    let streak: FireStreak

    var body: some View {
        HStack(spacing: 4) {
            PixelFire(flame: streak.flame, scale: 2)
            if streak.flame != .out {
                Text("\(streak.days)")
                    .font(.poppins(.headline).monospacedDigit())
                    .foregroundStyle(streak.flame == .embers ? Theme.ink3 : Theme.ink)
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, streak.flame == .out ? 6 : 10)
        .frame(height: 36)
        .background(Theme.card, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.line))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(streak.spoken)
    }
}

/// The fire, its message and the week, as one card on Today. Replaces the plain week strip.
struct FireCard: View {
    let streak: FireStreak
    /// Oldest first, ending today.
    let week: [Bool]

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            PixelFire(flame: streak.flame, scale: 4)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(streak.title)
                        .font(.poppins(.headline))
                        .foregroundStyle(Theme.ink)
                    Spacer(minLength: 8)
                    if streak.best > 0 {
                        Text("Best \(streak.best)")
                            .font(.poppins(.footnote))
                            .foregroundStyle(Theme.ink3)
                    }
                }
                Text(streak.message)
                    .font(.poppins(.footnote))
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 5) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, taught in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(taught ? Theme.finn : Theme.rule)
                            .frame(width: 14, height: 14)
                    }
                    Text("\(week.filter { $0 }.count) of 7 days")
                        .font(.poppins(.footnote))
                        .foregroundStyle(Theme.ink3)
                        .padding(.leading, 4)
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous)
                .strokeBorder(Theme.line)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(streak.spoken) Taught on \(week.filter { $0 }.count) of the last 7 days.")
    }
}
