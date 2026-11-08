import Foundation
import SwiftUI

/// Small helpers adapted from Regulur's extension files
/// (`Regulur/Classes/Extension/`). The UIKit-only ones (UIButton,
/// UIImageView, UIViewController) were dropped — v1 is SwiftUI. The
/// survivors below were rewritten for modern Swift: the originals used
/// `substring(_:)`, `scanHexInt32` and other Swift 4 APIs that no longer
/// exist, and force-unwrapped on bad input. These don't.

extension Color {
    /// `Color(hex: "#2F6BFF")` — supports #RGB and #RRGGBB.
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RRGGBB
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // AARRGGBB
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255,
                  blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

extension Date {
    var millisecondsSince1970: Int {
        Int((timeIntervalSince1970 * 1000.0).rounded())
    }
}

extension String {
    /// Ticker input cleanup: uppercase, no spaces, no "$".
    /// Mirrors the server's `clean_symbol` (letters/digits, ".", "-").
    var cleanedTicker: String {
        let cleaned = uppercased()
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: " ", with: "")
        return cleaned.filter { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }
    }

    var isValidEmail: Bool {
        let regex = try? NSRegularExpression(
            pattern: "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}",
            options: .caseInsensitive)
        guard let regex else { return false }
        return regex.firstMatch(in: self, range: NSRange(location: 0, length: count)) != nil
    }

    /// "$1,234.56" / "$12.40" for prices; nil-safe callers pass a value.
    static func money(_ value: Double?, digits: Int = 2) -> String {
        guard let value else { return "—" }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencySymbol = "$"
        f.minimumFractionDigits = digits
        f.maximumFractionDigits = digits
        return f.string(from: NSNumber(value: value)) ?? "$\(value)"
    }

    /// Compact large numbers: 12,400,000 → "$12.4M", 850,000 → "$850K".
    static func compactMoney(_ value: Double?) -> String {
        guard let value else { return "—" }
        if value >= 1_000_000_000 { return String(format: "$%.1fB", value / 1_000_000_000) }
        if value >= 1_000_000 { return String(format: "$%.1fM", value / 1_000_000) }
        if value >= 1_000 { return String(format: "$%.0fK", value / 1_000) }
        return money(value, digits: 0)
    }
}

extension Double {
    /// "+2.4%" / "−1.8%" — direction text uses this with NSColor.up/down.
    var signedPercent: String { String(format: "%+.1f%%", self) }
    var price: String { String(format: "$%.2f", self) }
}
