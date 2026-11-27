import SwiftUI
import UIKit
import GoldfishCore

// The UI style comes from a Figma Community file ("An Educational APP Authentication &
// Onboarding Mobile UI"): deep purple, white screens, Poppins, cards with soft borders.
// Finn and the marks come from the 8-bit prototype (PixelArt.swift).
// Every colour has a light and a dark value and follows the phone's appearance. Finn's pixels do not change.
// These values are the app's design tokens.

enum Theme {
    // MARK: Brand, from the Figma file

    /// "Branda": fills of primary buttons, selected states and tags. Brighter in dark mode so it still stands out.
    static let brand = Color(light: 0x491B6D, dark: 0x6E3AA6)
    /// Field borders and labels.
    static let brand2 = Color(light: 0x66328E, dark: 0xB68BDA)
    /// "Branda 2": pills that sit on purple.
    static let brand3 = Color(light: 0xC983DE, dark: 0xC983DE)
    /// Purple text on the screen: links, quiet section links, big numbers.
    static let link = Color(light: 0x491B6D, dark: 0xD4A9F2)
    /// The app's tint: text buttons, toggles, the selected tab.
    static let accent = link
    /// The purple banner and splash. Deeper in dark mode, so it does not glare.
    static let banner = Color(light: 0x491B6D, dark: 0x33134F)
    /// The banner's second circle.
    static let bannerGlow = Color(light: 0x66328E, dark: 0x4A2072)

    // MARK: Surfaces

    /// A screen's background.
    static let surface = Color(light: 0xFFFFFF, dark: 0x120E17)
    /// Cards, fields and options. The same as the screen in light mode, one step up in dark mode.
    static let card = Color(light: 0xFFFFFF, dark: 0x1D1724)
    /// Finn's speech and other soft fills.
    static let lavender = Color(light: 0xEEE8F6, dark: 0x2C2240)
    /// Stat tiles.
    static let frost = Color(light: 0xF0F4FD, dark: 0x1C2034)
    /// Card borders and icon tiles.
    static let line = Color(light: 0xF1F1F1, dark: 0x2D2537)
    /// Option borders and empty days.
    static let rule = Color(light: 0xE6E6E6, dark: 0x3A3145)
    /// Inactive page dots.
    static let dot = Color(light: 0xD9D9D9, dark: 0x4C4259)

    // MARK: Text

    static let ink = Color(light: 0x000000, dark: 0xFFFFFF)
    static let ink2 = Color(light: 0x4B4B4B, dark: 0xCFC8D8)
    static let ink3 = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.55) : UIColor(white: 0, alpha: 0.5)
    })

    // MARK: Finn and the student's words

    /// Finn's orange. Only for Finn and what he is doing, such as days you taught him.
    static let finn = Color(hex: FinnPalette.orange)
    /// Pixel water, for anything that stands for his tank.
    static let water = Color(hex: FinnPalette.water)
    /// The student's own words sit on paper. Nothing else is this colour.
    static let paper = Color(light: 0xFBF1DE, dark: 0x2B2318)
    static let paperLine = Color(light: 0xEAD4AA, dark: 0x5B4A30)
    static let paperInk = Color(light: 0x3A2A14, dark: 0xF2E2C2)
    static let paperHint = Color(light: 0xB89A6A, dark: 0x9A8460)
    /// The sentence Finn used, lit up on the paper. A highlighter looks the same in both modes.
    static let highlight = Color(hex: 0xFEE761)
    static let highlightInk = Color(hex: 0x7A2E12)

    // MARK: Tiers and verdicts

    static let onDevice = Color(light: 0x2F7A3A, dark: 0x7ED48B)
    static let cloud = Color(light: 0x4255C4, dark: 0xA3B0FF)

    static let radiusSmall: CGFloat = 5
    static let radiusMedium: CGFloat = 10
    static let radiusLarge: CGFloat = 18

    /// A strong colour for text and a pale one behind it.
    struct Tint {
        let text: Color
        let fill: Color
    }

    static let correctTint = Tint(text: Color(light: 0x2F7A3A, dark: 0x7ED48B), fill: Color(light: 0xE5F3E1, dark: 0x1C3321))
    static let mixUpTint = Tint(text: Color(light: 0xC2501B, dark: 0xFF9B66), fill: Color(light: 0xFDEADB, dark: 0x3B2216))
    static let gapTint = Tint(text: Color(light: 0x6E6A78, dark: 0xB5AFBF), fill: Color(light: 0xEFEEF2, dark: 0x2A2632))
    static let taughtTint = Tint(text: Color(light: 0x0B6CAB, dark: 0x6CC6F5), fill: Color(light: 0xE1F2FB, dark: 0x12304A))
    static let recalledTint = Tint(text: Color(light: 0x9B3F7A, dark: 0xE9A0CC), fill: Color(light: 0xF6E4EF, dark: 0x3A1C31))
    static let masteredTint = Tint(text: Color(light: 0x8A5E00, dark: 0xF2C54B), fill: Color(light: 0xFFF3C9, dark: 0x3A2E0E))
    static let onDeviceTint = Tint(text: onDevice, fill: Color(light: 0xE5F3E1, dark: 0x1C3321))
    static let cloudTint = Tint(text: cloud, fill: Color(light: 0xE8ECFB, dark: 0x1F2650))

    static func tint(for verdict: FishVerdict) -> Tint {
        switch verdict {
        case .correct: return correctTint
        case .mixUp: return mixUpTint
        case .gap: return gapTint
        }
    }

    static func tint(for state: ConceptState) -> Tint {
        switch state {
        case .notTaught: return gapTint
        case .taught: return taughtTint
        case .recalled: return recalledTint
        case .mastered: return masteredTint
        }
    }

    static func tint(for tier: FishTier) -> Tint {
        switch tier {
        case .onDevice: return onDeviceTint
        case .cloud: return cloudTint
        case .scripted: return gapTint
        }
    }

    /// A deck's colour. Lighter in dark mode, so it still reads on the dark screen.
    static func color(for deck: DeckColor) -> Color {
        switch deck {
        case .blue: return Color(light: 0x2F6FDB, dark: 0x6EA2FF)
        case .teal: return Color(light: 0x0F8C8C, dark: 0x3CC9C2)
        case .green: return Color(light: 0x2E8B47, dark: 0x5FCB78)
        case .yellow: return Color(light: 0xE0AA00, dark: 0xF2C94C)
        case .red: return Color(light: 0xD93F44, dark: 0xFF7A7E)
        case .pink: return Color(light: 0xC93C8E, dark: 0xF07ABF)
        case .indigo: return Color(light: 0x4B4FD1, dark: 0x8F93FF)
        case .grey: return Color(light: 0x6B6676, dark: 0xA8A2B3)
        }
    }

    /// The letter on a deck's colour: white in light mode, dark in dark mode, and dark on yellow always.
    static func ink(for deck: DeckColor) -> Color {
        deck == .yellow ? Color(hex: 0x2A1F00) : Color(light: 0xFFFFFF, dark: 0x120E17)
    }

    static func color(for verdict: FishVerdict) -> Color {
        tint(for: verdict).text
    }

    static func color(for state: ConceptState) -> Color {
        tint(for: state).text
    }

    static func color(for tier: FishTier) -> Color {
        tint(for: tier).text
    }
}

extension Color {
    /// A colour from 0xRRGGBB.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }

    /// A colour that follows the phone's appearance.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    /// A colour from 0xRRGGBB.
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Cards and buttons

/// The Figma card: white, a one-point border and 18-point corners. Flat cards are the pale stat tiles.
struct Card<Content: View>: View {
    var flat = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(flat ? Theme.frost : Theme.card, in: RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
        .overlay {
            if !flat {
                RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous)
                    .strokeBorder(Theme.line)
            }
        }
    }
}

/// Purple, 50 points tall, 10-point corners. Compact is the "Next" button of the first run.
struct PrimaryButtonStyle: ButtonStyle {
    let compact: Bool
    @Environment(\.isEnabled) private var isEnabled

    init(compact: Bool = false) {
        self.compact = compact
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.poppins(.callout, weight: compact ? .bold : .semibold))
            .multilineTextAlignment(.center)
            .frame(maxWidth: compact ? nil : .infinity)
            .frame(minHeight: compact ? 44 : 50)
            .padding(.horizontal, compact ? 28 : 16)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous)
                    .fill(isEnabled ? Theme.brand : Theme.brand.opacity(0.35))
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
            .contentShape(Rectangle())
    }
}

/// White with a purple outline. The second choice beside a primary button.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.poppins(.callout, weight: .semibold))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 50)
            .padding(.horizontal, 16)
            .foregroundStyle(isEnabled ? Theme.link : Theme.ink3)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous)
                    .fill(Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous)
                    .strokeBorder(isEnabled ? Theme.link : Theme.rule, lineWidth: 1.5)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle {
        PrimaryButtonStyle()
    }

    static var primaryCompact: PrimaryButtonStyle {
        PrimaryButtonStyle(compact: true)
    }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle {
        SecondaryButtonStyle()
    }
}

// MARK: - Small parts

/// A small rounded label: a verdict, a state or a tier. It can carry a pixel mark or an SF Symbol.
struct Pill: View {
    let text: String
    let tint: Theme.Tint
    var mark: PixelSprite?
    var systemImage: String?

    var body: some View {
        HStack(spacing: 5) {
            if let mark = mark {
                PixelMark(sprite: mark, scale: mark.height > 10 ? 1 : 2)
            } else if let systemImage = systemImage {
                Image(systemName: systemImage)
            }
            Text(text)
                .lineLimit(1)
        }
        .font(.poppins(.caption, weight: .semibold))
        .foregroundStyle(tint.text)
        .padding(.horizontal, 9)
        .frame(minHeight: 24)
        .background(tint.fill, in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
    }
}

/// A section title with a quiet link on the right, like "Course" and "View All" in the Figma home page.
struct SectionHeader: View {
    let title: String
    var detail: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.poppins(.title2))
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let detail = detail {
                if let action = action {
                    Button(detail, action: action)
                        .font(.poppins(.callout, weight: .medium))
                        .foregroundStyle(Theme.link.opacity(0.7))
                } else {
                    Text(detail)
                        .font(.poppins(.callout, weight: .medium))
                        .foregroundStyle(Theme.link.opacity(0.7))
                }
            }
        }
    }
}

/// The Figma icon tile: a rounded square that holds a pixel mark at the start of a list card.
struct IconTile<Content: View>: View {
    var size: CGFloat = 68
    var fill: Color = Theme.line
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(width: size, height: size)
            .background(fill, in: RoundedRectangle(cornerRadius: size > 50 ? 13 : 12, style: .continuous))
    }
}

/// The Figma list card: an icon tile, a bold title, a detail line and a chevron.
struct ListCard<Tile: View, Detail: View>: View {
    let title: String
    let tile: Tile
    let detail: Detail

    init(_ title: String, @ViewBuilder tile: () -> Tile, @ViewBuilder detail: () -> Detail) {
        self.title = title
        self.tile = tile()
        self.detail = detail()
    }

    var body: some View {
        HStack(spacing: 16) {
            IconTile {
                tile
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.poppins(.headline))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                detail
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.ink3)
                .accessibilityHidden(true)
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous)
                .strokeBorder(Theme.line)
        )
        .contentShape(Rectangle())
    }
}

/// The Figma carousel dots: the current page is a purple bar.
struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? Theme.brand : Theme.dot)
                    .frame(width: index == current ? 22 : 8, height: 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(current + 1) of \(count)")
    }
}

/// The Figma labelled field: a purple label above a box with a purple border.
struct LabeledField<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.poppins(.subheadline))
                .foregroundStyle(Theme.brand2)
            HStack(spacing: 12) {
                content
            }
            .font(.poppins(.callout, weight: .medium))
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous)
                    .strokeBorder(Theme.brand2, lineWidth: 1)
            )
        }
    }
}

extension View {
    /// The student's own words: cream paper with a tan edge.
    func paperStyle() -> some View {
        self
            .font(.poppins(.callout))
            .foregroundStyle(Theme.paperInk)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Theme.paper, in: RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous)
                    .strokeBorder(Theme.paperLine, lineWidth: 1)
            )
    }

    /// A screen's background: plain white, as in the Figma file.
    func screenBackground() -> some View {
        background(Theme.surface.ignoresSafeArea())
    }
}
