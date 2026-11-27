import SwiftUI

/// Orla, the tutor goldfish: a red-cap Oranda with round glasses. She coaches; Finn learns.
/// Her pixels come from ORLA_MOODS in tools/art/finn8.js, through FinnSprites.swift.
enum OrlaMood: CaseIterable {
    case calm
    case thinking
    case asking
    case hinting
    case pleased

    var spoken: String {
        switch self {
        case .calm: return "calm"
        case .thinking: return "thoughtful"
        case .asking: return "curious, with a question"
        case .hinting: return "like she has a hint"
        case .pleased: return "pleased"
        }
    }
}

/// Which eye and bubble an Orla mood uses. FinnSprites.swift gives one for each OrlaMood.
struct OrlaLook {
    let eye: String
    /// A letter for the bubble, "bulb" for a hint, "*" for sparkles, nil for none.
    let icon: String?
}

enum OrlaPainter {
    /// The layers of one frame of Orla, in pixels from her top-left corner. Mirrors orlaLayers in finn8.js.
    static func layers(_ mood: OrlaMood, time: Double?, showsBubble: Bool = true) -> [FinnPainter.Layer] {
        let look = mood.pixelLook
        let still = time == nil
        let t = time ?? 0
        let tail = still ? 0 : FinnPainter.step(t, OrlaSprites.tailSteps, 2)
        let bob = still ? 0 : FinnPainter.step(t, FinnSprites.bobSteps, 2)
        var eye = look.eye
        let blinkPhase = (t + OrlaSprites.blinkOffset).truncatingRemainder(dividingBy: OrlaSprites.blinkEvery)
        if !still && eye != "happy" && blinkPhase > OrlaSprites.blinkEvery - FinnSprites.blinkFor {
            eye = "shut"
        }
        var layers: [FinnPainter.Layer] = []
        if let body = OrlaSprites.bodies["\(tail)-\(eye)"] {
            layers.append((body, 0, bob))
        }
        guard showsBubble, let icon = look.icon else { return layers }
        let ix = OrlaSprites.bubbleAt.x
        let iy = OrlaSprites.bubbleAt.y + bob
        if icon == "*" {
            let beat = still ? 0 : FinnPainter.step(t, FinnSprites.sparkleSteps, 3)
            layers.append((beat == 0 ? FinnSprites.sparkle : FinnSprites.spark, ix + 2, iy + 1))
            layers.append((beat == 1 ? FinnSprites.sparkle : FinnSprites.spark, ix + 7, iy + 7))
            layers.append((beat == 2 ? FinnSprites.sparkle : FinnSprites.spark, ix - 5, iy - 1))
        } else {
            layers.append((FinnSprites.bubble, ix, iy))
            if icon == "bulb" {
                layers.append((FinnSprites.bulb, ix + 2, iy + 1))
            } else if let glyph = FinnSprites.glyphs[icon] {
                layers.append((glyph, ix + 2, iy + 1))
            }
        }
        return layers
    }

    static func draw(_ mood: OrlaMood, x: Int, y: Int, time: Double?, showsBubble: Bool = true, pen: PixelPen) {
        for layer in layers(mood, time: time, showsBubble: showsBubble) {
            pen.sprite(layer.sprite, x: x + layer.x, y: y + layer.y)
        }
    }
}

/// Orla on her own, with no water. For a large Orla, use PixelTank(orla:).
struct OrlaView: View {
    var mood: OrlaMood = .calm
    /// About how wide the view is, in points. It is rounded so each sprite pixel is a whole number of points.
    var size: CGFloat = 80
    var showsBubble = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var scale: CGFloat {
        max(1, (size * 1.3 / CGFloat(OrlaSprites.frame.width)).rounded())
    }

    var body: some View {
        let frame = OrlaSprites.frame
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
        .accessibilityLabel("Orla, the tutor, looks \(mood.spoken)")
    }

    private func canvas(time: Double?) -> some View {
        Canvas { context, _ in
            let pen = PixelPen(context: context, scale: scale)
            OrlaPainter.draw(mood, x: -OrlaSprites.frame.x, y: -OrlaSprites.frame.y, time: time, showsBubble: showsBubble, pen: pen)
        }
    }
}

/// Orla's lines: the same lavender bubble as Finn's, with her name on the tag.
struct OrlaSays: View {
    let text: String
    var mood: OrlaMood = .calm
    var size: CGFloat = 48

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            OrlaView(mood: mood, size: size)
            SpeechBubble(text: text, tail: .leading, name: "Orla")
        }
        .accessibilityElement(children: .combine)
    }
}
