import SwiftUI

/// NextShelf design tokens.
///
/// Colours live in the asset catalog (Assets.xcassets) with light/dark
/// variants, so the app follows the system appearance. The values below
/// are the brand palette from the logo set + mockup:
///
///   paper  #F6F6F3 (light) / #0E1116 (dark)
///   card   #FFFFFF        / #171B22
///   ink    #1A1C22        / #F2F3F5
///   muted  #6E746E        / #9AA0AB
///   line   #E7E0D6        / #262B34
///   blue   #2F6BFF (brand, both appearances)
///   green  #22C55E — direction percentages ONLY, never status
///   red    #DC2626 — direction percentages ONLY, never status
///   amber  #D97706 — warnings (earnings blackout, beta tags)
///
/// Lineage: the *approach* (one named-colour struct the whole app reads
/// from) is the Regulur `ColorsConfig` pattern from
/// `Regulur/Style/RegulurStyle.swift`. The colours themselves are
/// NextShelf's; no Regulur colour value survives.
enum NSColor {
    static let paper = Color("Paper")
    static let card = Color("Card")
    static let ink = Color("Ink")
    static let muted = Color("Muted")
    static let line = Color("Line")
    static let blue = Color("BrandBlue")
    /// Green is reserved for direction (up / positive %) only.
    static let up = Color("UpGreen")
    /// Red is reserved for direction (down / negative %) only.
    static let down = Color("DownRed")
    static let amber = Color("Amber")
}

enum NSFont {
    /// Brand serif for the wordmark / big headings only (Fraunces on the
    /// web; Georgia is the closest system serif on iOS).
    static let serif = Font.system(.largeTitle, design: .serif)
    static func serif(size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

enum NSLayout {
    static let cornerRadius: CGFloat = 18
    static let smallRadius: CGFloat = 12
    static let screenPadding: CGFloat = 16
}
