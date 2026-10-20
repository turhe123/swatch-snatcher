import SwiftUI

/// An sRGB color with components in 0...1; the unit stored in history and palettes.
struct RGBColor: Codable, Hashable, Identifiable {
    var r: Double
    var g: Double
    var b: Double

    var id: String { hex }

    private var bytes: (Int, Int, Int) {
        (Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    var hex: String {
        let (r8, g8, b8) = bytes
        return String(format: "#%02X%02X%02X", r8, g8, b8)
    }

    var swiftUIColor: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: 1) }

    /// WCAG 2.x relative luminance.
    var luminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    /// WCAG contrast ratio between two colors (1...21).
    func contrast(with other: RGBColor) -> Double {
        let (hi, lo) = (max(luminance, other.luminance), min(luminance, other.luminance))
        return (hi + 0.05) / (lo + 0.05)
    }

    /// Hue (0...360), saturation and lightness (0...1).
    var hsl: (Double, Double, Double) {
        let maxC = max(r, g, b), minC = min(r, g, b), d = maxC - minC
        let l = (maxC + minC) / 2
        guard d > 0 else { return (0, 0, l) }
        let s = d / (1 - abs(2 * l - 1))
        var h: Double
        switch maxC {
        case r: h = ((g - b) / d).truncatingRemainder(dividingBy: 6)
        case g: h = (b - r) / d + 2
        default: h = (r - g) / d + 4
        }
        h *= 60
        if h < 0 { h += 360 }
        return (h, s, l)
    }

    func formatted(_ format: ColorFormat) -> String {
        let (r8, g8, b8) = bytes
        func f(_ v: Double) -> String { String(format: "%.3f", v) }
        switch format {
        case .hex: return hex
        case .rgb: return "rgb(\(r8), \(g8), \(b8))"
        case .hsl:
            let (h, s, l) = hsl
            return "hsl(\(Int(h.rounded())), \(Int((s * 100).rounded()))%, \(Int((l * 100).rounded()))%)"
        case .swiftUI: return "Color(red: \(f(r)), green: \(f(g)), blue: \(f(b)))"
        case .nsColor: return "NSColor(srgbRed: \(f(r)), green: \(f(g)), blue: \(f(b)), alpha: 1.0)"
        }
    }
}

/// The text formats a picked color can be copied as.
enum ColorFormat: String, CaseIterable, Identifiable {
    case hex = "HEX", rgb = "RGB", hsl = "HSL", swiftUI = "SwiftUI", nsColor = "NSColor"
    var id: String { rawValue }
}

/// A user-named collection of pinned colors.
struct Palette: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var colors: [RGBColor] = []
}

/// The on-disk JSON document holding history and palettes.
struct Library: Codable {
    var history: [RGBColor] = []
    var palettes: [Palette] = []
}
