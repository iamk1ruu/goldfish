import CoreText
import SwiftUI
import UIKit

/// Poppins, the typeface of the Figma file. Four weights are bundled in App/Resources/Fonts
/// under the SIL Open Font License (OFL.txt beside them).
/// They are registered at launch, so the app needs no UIAppFonts entry in its Info.plist.
enum AppFonts {
    /// Registers the bundled fonts and styles the navigation bars. Call once, before any view appears.
    static func register() {
        let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        styleNavigationBars()
    }

    /// The PostScript name for a weight. Poppins is bundled in four weights.
    static func name(_ weight: Font.Weight) -> String {
        switch weight {
        case .bold, .heavy, .black: return "Poppins-Bold"
        case .semibold: return "Poppins-SemiBold"
        case .medium: return "Poppins-Medium"
        default: return "Poppins-Regular"
        }
    }

    /// The Figma type scale, by text style. Sizes still follow Dynamic Type.
    static func spec(_ style: Font.TextStyle) -> (size: CGFloat, weight: Font.Weight) {
        switch style {
        case .largeTitle: return (32, .bold)
        case .title: return (24, .bold)
        case .title2: return (22, .bold)
        case .title3: return (18, .semibold)
        case .headline: return (16, .bold)
        case .body: return (16, .regular)
        case .callout: return (15, .regular)
        case .subheadline: return (14, .medium)
        case .footnote: return (13, .medium)
        case .caption: return (12, .medium)
        case .caption2: return (11, .semibold)
        default: return (16, .regular)
        }
    }

    /// Poppins titles in the navigation bars. Only the fonts are set: the bars keep the system's Liquid Glass
    /// background, and `.label` follows light and dark mode.
    private static func styleNavigationBars() {
        let bar = UINavigationBar.appearance()
        bar.titleTextAttributes = [
            .font: UIFont(name: "Poppins-SemiBold", size: 18) ?? UIFont.systemFont(ofSize: 18, weight: .semibold),
            .foregroundColor: UIColor.label,
        ]
        bar.largeTitleTextAttributes = [
            .font: UIFont(name: "Poppins-Bold", size: 30) ?? UIFont.systemFont(ofSize: 30, weight: .bold),
            .foregroundColor: UIColor.label,
        ]
    }
}

extension Font {
    /// Poppins at the size and weight the Figma type scale gives this text style.
    static func poppins(_ style: Font.TextStyle, weight: Font.Weight? = nil) -> Font {
        let spec = AppFonts.spec(style)
        return .custom(AppFonts.name(weight ?? spec.weight), size: spec.size, relativeTo: style)
    }

    /// Poppins at a set size, for display numbers and tags.
    static func poppins(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(AppFonts.name(weight), size: size)
    }
}
