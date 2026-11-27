import SwiftUI

// Draws the 8-bit art: Finn, his tank and the small marks.
// The sprite rows are generated into FinnSprites.swift from tools/art/finn8.js. The drawing code here
// mirrors drawSprite, fishLayers and tank in that file, so the app shows the pixels the UI kit shows.
// If one changes, change the other.

struct PixelPoint {
    let x: Int
    let y: Int
}

struct PixelBox {
    let x: Int
    let y: Int
    let width: Int
    let height: Int
}

/// Which eye, mouth, bubble and extras a mood uses. FinnSprites.swift gives one for each FishMood.
struct PixelLook {
    let eye: String
    let mouth: String
    /// A letter for the bubble, " " for an empty bubble, "*" for sparkles, "~" for a popping memory, nil for none.
    let icon: String?
    let cap: Bool
    let lens: Bool
    let headband: Bool
}

/// A sprite from rows of colour letters, with "." for an empty pixel.
/// The rows are padded by one pixel, so row r, column c is drawn at (x + c - 1, y + r - 1).
struct PixelSprite {
    struct Run {
        let x: Int
        let y: Int
        let length: Int
        let color: Color
    }

    let width: Int
    let height: Int
    /// Runs of one colour along a row, so a sprite is a few dozen rectangles rather than hundreds.
    let runs: [Run]

    init(_ rows: [String]) {
        width = rows.first?.count ?? 0
        height = rows.count
        var runs: [Run] = []
        for (y, row) in rows.enumerated() {
            let letters = Array(row)
            var x = 0
            while x < letters.count {
                let letter = letters[x]
                var end = x + 1
                while end < letters.count && letters[end] == letter {
                    end += 1
                }
                if letter != ".", let rgb = FinnPalette.letters[letter] {
                    runs.append(Run(x: x, y: y, length: end - x, color: Color(hex: rgb)))
                }
                x = end
            }
        }
        self.runs = runs
    }
}

/// Draws whole pixels into a Canvas. One sprite pixel is `scale` points, with no smoothing.
struct PixelPen {
    let context: GraphicsContext
    let scale: CGFloat

    func rect(_ x: Int, _ y: Int, _ width: Int, _ height: Int, _ color: Color) {
        guard width > 0, height > 0 else { return }
        let box = CGRect(
            x: CGFloat(x) * scale, y: CGFloat(y) * scale,
            width: CGFloat(width) * scale, height: CGFloat(height) * scale
        )
        context.fill(Path(box), with: .color(color), style: FillStyle(antialiased: false))
    }

    func sprite(_ sprite: PixelSprite, x: Int, y: Int, flip: Bool = false) {
        for run in sprite.runs {
            let column = flip ? sprite.width - run.x - run.length : run.x
            rect(x + column - 1, y + run.y - 1, run.length, 1, run.color)
        }
    }
}

// MARK: - Finn

enum FinnPainter {
    typealias Layer = (sprite: PixelSprite, x: Int, y: Int)

    /// The layers of one frame of Finn, in fish pixels from his top-left corner. With no time he holds still.
    /// The same steps as fishLayers in finn8.js.
    static func layers(_ mood: FishMood, time: Double?, showsBubble: Bool = true) -> [Layer] {
        let look = mood.pixelLook
        let still = time == nil
        let t = time ?? 0
        let tail = still ? 0 : step(t, FinnSprites.tailSteps, 2)
        let bob = still ? 0 : step(t, FinnSprites.bobSteps, 2)
        var eye = look.eye
        let canBlink = eye != "happy" && eye != "shut"
        if !still && canBlink && t.truncatingRemainder(dividingBy: FinnSprites.blinkEvery) > FinnSprites.blinkEvery - FinnSprites.blinkFor {
            eye = "shut"
        }

        var layers: [Layer] = []
        if let body = FinnSprites.bodies["\(tail)-\(eye)-\(look.mouth)"] {
            layers.append((body, 0, bob))
        }
        if look.headband {
            layers.append((FinnSprites.headband, FinnSprites.headbandAt.x, FinnSprites.headbandAt.y + bob))
        }
        if look.cap {
            layers.append((FinnSprites.cap, FinnSprites.capAt.x, FinnSprites.capAt.y + bob))
        }
        if look.lens {
            layers.append((FinnSprites.lens, FinnSprites.lensAt.x, FinnSprites.lensAt.y + bob))
        }
        guard showsBubble, let icon = look.icon else { return layers }

        let ix = FinnSprites.bubbleAt.x
        let iy = FinnSprites.bubbleAt.y + bob
        switch icon {
        case "*":
            let beat = still ? 0 : step(t, FinnSprites.sparkleSteps, 3)
            layers.append((beat == 0 ? FinnSprites.sparkle : FinnSprites.spark, ix + 2, iy + 1))
            layers.append((beat == 1 ? FinnSprites.sparkle : FinnSprites.spark, ix + 8, iy + 7))
            layers.append((beat == 2 ? FinnSprites.sparkle : FinnSprites.spark, ix - 5, iy - 2))
        case "~":
            let beat = still ? 0 : step(t, FinnSprites.popSteps, 3)
            if beat == 0 {
                layers.append((FinnSprites.bubble, ix, iy))
            } else if beat == 1 {
                layers.append((FinnSprites.popping, ix, iy))
            }
        default:
            layers.append((FinnSprites.bubble, ix, iy))
            if icon != " ", let glyph = FinnSprites.glyphs[icon] {
                layers.append((glyph, ix + 2, iy + 1))
            }
        }
        return layers
    }

    static func draw(_ mood: FishMood, x: Int, y: Int, time: Double?, showsBubble: Bool = true, pen: PixelPen) {
        for layer in layers(mood, time: time, showsBubble: showsBubble) {
            pen.sprite(layer.sprite, x: x + layer.x, y: y + layer.y)
        }
    }

    /// Which of `count` frames is showing, stepping `perSecond` times a second.
    static func step(_ time: Double, _ perSecond: Double, _ count: Int) -> Int {
        Int(floor(time * perSecond)) % count
    }
}

// MARK: - The tank

enum TankPainter {
    /// Water with a moving surface, a sand floor, weeds and rising bubbles. Mirrors tank in finn8.js.
    /// `weeds` are offsets in pixels from the left edge.
    static func draw(
        pen: PixelPen, x: Int, y: Int, width w: Int, height h: Int, time t: Double,
        surface: Bool = false, sky: Color = Color(hex: FinnPalette.ink), weeds: [Int] = [], bubbles: Int = 4
    ) {
        let deep = Color(hex: FinnPalette.deep)
        let sea = Color(hex: FinnPalette.sea)
        let water = Color(hex: FinnPalette.water)
        let first = Int((Double(h) * 0.36).rounded())
        let second = Int((Double(h) * 0.7).rounded())
        pen.rect(x, y, w, h, deep)
        pen.rect(x, y, w, first, water)
        pen.rect(x, y + first, w, second - first, sea)
        for i in stride(from: 0, to: w, by: 2) {
            pen.rect(x + i, y + first - 1, 1, 1, sea)
            pen.rect(x + i + 1, y + first, 1, 1, water)
            pen.rect(x + i, y + second - 1, 1, 1, deep)
            pen.rect(x + i + 1, y + second, 1, 1, sea)
        }
        if surface {
            let white = Color(hex: FinnPalette.white)
            let aqua = Color(hex: FinnPalette.aqua)
            let shift = Int(floor(t * 3))
            for i in 0..<max(w, 0) {
                let crest = ((i + shift) % 8) < 4
                if !crest {
                    pen.rect(x + i, y, 1, 1, sky)
                }
                pen.rect(x + i, y + (crest ? 0 : 1), 1, 1, white)
                pen.rect(x + i, y + (crest ? 1 : 2), 1, 1, aqua)
            }
        }
        let cream = Color(hex: FinnPalette.cream)
        let sand = Color(hex: FinnPalette.sand)
        pen.rect(x, y + h - 6, w, 6, cream)
        for i in stride(from: 0, to: w, by: 5) {
            pen.rect(x + i, y + h - 7, 2, 1, cream)
        }
        if w > 0 {
            for i in 0..<12 {
                pen.rect(x + ((i * 23 + 7) % w), y + h - 4 + (i % 2) * 2, 1, 1, sand)
            }
        }
        for (index, offset) in weeds.enumerated() {
            let flip = Int(floor(t * 1.5 + Double(index))) % 2 == 1
            pen.sprite(FinnSprites.weed, x: x + offset, y: y + h - 20, flip: flip)
        }
        for i in 0..<bubbles {
            let period = 5 + Double(i) * 1.3
            let progress = ((t + Double(i) * 2.1) / period).truncatingRemainder(dividingBy: 1)
            let bx = x + 3 + ((i * 37 + 17) % max(1, w - 12)) + Int(sin(t * 2 + Double(i)).rounded())
            let by = Double(y + h - 10) - progress * Double(h - 16)
            pen.sprite(i % 2 == 1 ? FinnSprites.ring3 : FinnSprites.ring5, x: bx, y: Int(by.rounded()))
        }
    }
}

/// Finn's water window. It fills the space it is given, at whole points per pixel.
/// Large Finn always lives in one of these.
struct PixelTank: View {
    var mood: FishMood? = .happy
    /// Points per pixel.
    var scale: CGFloat = 3
    /// Where Finn swims, as a share of the free room. (0, 0) is the top left.
    var fishAt = UnitPoint(x: 0.45, y: 0.62)
    /// Weed positions as shares of the width.
    var weeds: [CGFloat] = [0.04, 0.9]
    var bubbles = 4
    var showsBubble = true
    /// He jumps for joy, on the result screen.
    var jumps = false
    /// Orla swims here instead of Finn, on the Tutor tab.
    var orla: OrlaMood?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                scene(time: nil)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { timeline in
                    scene(time: timeline.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .accessibilityHidden(mood == nil && orla == nil)
        .accessibilityElement()
        .accessibilityLabel(spoken)
    }

    private var spoken: String {
        if let orla = orla {
            return "Orla, the tutor, looks \(orla.spoken)"
        }
        return mood.map { "The goldfish looks \($0.spoken)" } ?? ""
    }

    private func scene(time: Double?) -> some View {
        Canvas { context, size in
            let pen = PixelPen(context: context, scale: scale)
            let w = Int(size.width / scale)
            let h = Int(size.height / scale)
            let t = time ?? 1.2
            let weedOffsets = weeds.map { Int(($0 * CGFloat(max(w - 5, 0))).rounded()) }
            TankPainter.draw(pen: pen, x: 0, y: 0, width: w, height: h, time: t, weeds: weedOffsets, bubbles: reduceMotion ? 0 : bubbles)
            if let orla = orla {
                let ox = Int((CGFloat(max(w - 26, 0)) * fishAt.x).rounded())
                let oy = Int((CGFloat(max(h - 18, 0)) * fishAt.y).rounded())
                OrlaPainter.draw(orla, x: ox, y: oy, time: time, showsBubble: showsBubble, pen: pen)
                return
            }
            guard let mood = mood else { return }
            let fx = Int((CGFloat(max(w - 24, 0)) * fishAt.x).rounded())
            let fy = Int((CGFloat(max(h - 18, 0)) * fishAt.y).rounded())
            let lift = jumps && time != nil ? Int((abs(sin(t * 4)) * 4).rounded()) : 0
            FinnPainter.draw(mood, x: fx, y: fy - lift, time: time, showsBubble: showsBubble, pen: pen)
        }
    }
}

/// The cloud-tier wait: the cloud writes in the sky, pages sink through the waterline, Finn waits below.
struct PixelCloudScene: View {
    var scale: CGFloat = 3

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A pale day sky in light mode, a night sky in dark mode.
    private static let sky = Color(light: 0xDCE6FB, dark: 0x1A1F3A)
    private static let skyLow = Color(light: 0xC9D7F6, dark: 0x232A4D)
    private static let ink = Color(light: 0x7B8CE0, dark: 0x9AA8F0)

    var body: some View {
        Group {
            if reduceMotion {
                scene(time: nil)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { timeline in
                    scene(time: timeline.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func scene(time: Double?) -> some View {
        Canvas { context, size in
            let pen = PixelPen(context: context, scale: scale)
            let w = Int(size.width / scale)
            let h = Int(size.height / scale)
            let still = time == nil
            let t = time ?? 1.1
            let waterTop = Int(Double(h) * 0.43)
            pen.rect(0, 0, w, h, Self.sky)
            pen.rect(0, waterTop - 8, w, 8, Self.skyLow)
            TankPainter.draw(pen: pen, x: 0, y: waterTop, width: w, height: h - waterTop, time: t, surface: true, sky: Self.skyLow, weeds: [6, max(w - 17, 0)], bubbles: still ? 0 : 3)

            let cloudX = (w - 30) / 2
            let lift = still ? 0 : FinnPainter.step(t, 1.5, 2)
            pen.sprite(FinnSprites.cloud, x: cloudX, y: 4 + lift)
            for (i, length) in [12, 8, 10].enumerated() {
                let written = still ? length - i * 2 : min(length, Int(floor(t * 10 + Double(i) * 6)) % 24)
                pen.rect(cloudX + 8, 10 + lift + i * 2, written, 1, Self.ink)
            }
            for i in 0..<3 {
                let progress = (t / 3.2 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                guard progress > 0.04 && progress < 0.96 else { continue }
                let px = cloudX + 20 + Int((sin(progress * 6.28) * 4).rounded())
                let py = 18 + Int((progress * Double(h - 30)).rounded())
                pen.sprite(FinnSprites.page, x: px, y: py)
            }
            FinnPainter.draw(.curious, x: 14, y: h - 26, time: time, pen: pen)
        }
    }
}

// MARK: - Marks

/// One small sprite, such as a concept token, at whole points per pixel.
struct PixelMark: View {
    let sprite: PixelSprite
    var scale: CGFloat = 2

    var body: some View {
        Canvas { context, _ in
            PixelPen(context: context, scale: scale).sprite(sprite, x: 1, y: 1)
        }
        .frame(width: CGFloat(sprite.width) * scale, height: CGFloat(sprite.height) * scale)
        .accessibilityHidden(true)
    }
}
