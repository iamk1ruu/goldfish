import SwiftUI

/// Finn's moods. There is no sad or sick state on purpose.
/// Each mood's pixels come from MOODS in tools/art/finn8.js, through FinnSprites.swift.
enum FishMood: CaseIterable {
    case happy
    case curious
    case listening
    case thinking
    case proud
    case confused
    case shrug
    case forgetful
    case inspecting
    case graduate
    case focused
    case sleepy

    /// How VoiceOver describes him.
    var spoken: String {
        switch self {
        case .happy: return "happy"
        case .curious: return "curious"
        case .listening: return "ready to take notes"
        case .thinking: return "thoughtful"
        case .proud: return "proud"
        case .confused: return "puzzled"
        case .shrug: return "blank, because this was not taught"
        case .forgetful: return "forgetful"
        case .inspecting: return "like a detective"
        case .graduate: return "proud in a graduation cap"
        case .focused: return "focused"
        case .sleepy: return "asleep"
        }
    }
}

/// Finn on his own, with no water: the 24 by 18 pixel sprite plus his bubble.
/// His tail flicks, he bobs a pixel and he blinks, a few steps a second like a handheld game.
/// For a large Finn, put him in a PixelTank instead.
struct FishView: View {
    var mood: FishMood = .happy
    /// About how wide the view is, in points. It is rounded so each sprite pixel is a whole number of points.
    var size: CGFloat = 120
    var showsBubble = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Points per sprite pixel.
    private var scale: CGFloat {
        max(1, (size * 1.3 / CGFloat(FinnSprites.frame.width)).rounded())
    }

    var body: some View {
        let frame = FinnSprites.frame
        Group {
            if reduceMotion {
                canvas(time: nil)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { timeline in
                    canvas(time: timeline.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .frame(width: CGFloat(frame.width) * scale, height: CGFloat(frame.height) * scale)
        .accessibilityElement()
        .accessibilityLabel("The goldfish looks \(mood.spoken)")
    }

    private func canvas(time: Double?) -> some View {
        Canvas { context, _ in
            let pen = PixelPen(context: context, scale: scale)
            FinnPainter.draw(mood, x: -FinnSprites.frame.x, y: -FinnSprites.frame.y, time: time, showsBubble: showsBubble, pen: pen)
        }
    }
}

/// A rounded bubble with a small tail that points at the fish.
struct BubbleShape: Shape {
    var tail: Edge?

    func path(in rect: CGRect) -> Path {
        var path = Path(roundedRect: rect, cornerRadius: Theme.radiusMedium, style: .continuous)
        let reach: CGFloat = 7
        if tail == .leading {
            path.move(to: CGPoint(x: rect.minX + 1, y: rect.midY - reach))
            path.addLine(to: CGPoint(x: rect.minX - reach, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.minX + 1, y: rect.midY + reach))
            path.closeSubpath()
        } else if tail == .top {
            path.move(to: CGPoint(x: rect.midX - reach, y: rect.minY + 1))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.minY - reach))
            path.addLine(to: CGPoint(x: rect.midX + reach, y: rect.minY + 1))
            path.closeSubpath()
        }
        return path
    }
}

/// Finn's lines: a lavender bubble with his name on a purple tag, like a dialog box in a game.
struct SpeechBubble: View {
    let text: String
    /// The side the tail is on. It should point at the fish.
    var tail: Edge?
    /// The fish's name for the tag. No tag when nil.
    var name: String?

    var body: some View {
        Text(text)
            .font(.poppins(.callout, weight: .medium))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 14)
            .padding(.top, name == nil ? 12 : 14)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BubbleShape(tail: tail).fill(Theme.lavender))
            .overlay(alignment: .topLeading) {
                if let name = name {
                    NameTag(name: name)
                        .offset(x: 12, y: -10)
                }
            }
            .padding(.top, name == nil ? 0 : 10)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The purple tag with the fish's name on it.
struct NameTag: View {
    let name: String

    var body: some View {
        Text(name.uppercased())
            .font(.poppins(size: 10, weight: .semibold))
            .tracking(0.8)
            .lineLimit(1)
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(Theme.brand, in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// The fish with a line of dialogue beside it. He faces the bubble.
struct FishSays: View {
    @Environment(AppModel.self) private var model
    let text: String
    var mood: FishMood = .happy
    var size: CGFloat = 80

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            FishView(mood: mood, size: size)
            SpeechBubble(text: text, tail: .leading, name: model.fishName)
        }
        .accessibilityElement(children: .combine)
    }
}
