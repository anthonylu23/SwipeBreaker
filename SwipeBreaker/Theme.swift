import SwiftUI
import SpriteKit

#if canImport(UIKit)
import UIKit
typealias PlatformColor = UIColor
#else
import AppKit
typealias PlatformColor = NSColor
#endif

enum Theme {
    enum Mode { case light, dark }

    struct Palette {
        let background: Color
        let surface: Color
        let elevated: Color
        let primary: Color
        let primaryForeground: Color
        let accent: Color
        let launcher: Color
        let pickup: Color
        let textPrimary: Color
        let textSecondary: Color
        let border: Color
        let destructive: Color
        let glow: Color
    }

    static let light = Palette(
        background:        Color(hex: 0xEAE3D7),
        surface:           Color(hex: 0xF3F1ED),
        elevated:          Color(hex: 0xF6F5F3),
        primary:           Color(hex: 0xE89117),
        primaryForeground: Color(hex: 0x2F2823),
        accent:            Color(hex: 0xE89117),
        launcher:          Color(hex: 0xF2B35A),
        pickup:            Color(hex: 0xC08A1C),
        textPrimary:       Color(hex: 0x2F2823),
        textSecondary:     Color(hex: 0x746963),
        border:            Color(hex: 0xD1C9BD),
        destructive:       Color(hex: 0xCD231D),
        glow:              Color(hex: 0xE89117)
    )

    static let dark = Palette(
        background:        Color(hex: 0x393C3C),
        surface:           Color(hex: 0x434646),
        elevated:          Color(hex: 0x4B4E4E),
        primary:           Color(hex: 0x00B8AB),
        primaryForeground: Color(hex: 0x121616),
        accent:            Color(hex: 0x00B8AB),
        launcher:          Color(hex: 0x5FDDD2),
        pickup:            Color(hex: 0xFFE073),
        textPrimary:       Color(hex: 0xE8E6E3),
        textSecondary:     Color(hex: 0xB6B3AF),
        border:            Color(hex: 0x5E6368),
        destructive:       Color(hex: 0xC7271F),
        glow:              Color(hex: 0x00B8A8)
    )

    static func palette(for mode: Mode) -> Palette { mode == .light ? light : dark }

    static func palette(for scheme: ColorScheme) -> Palette {
        scheme == .light ? light : dark
    }

    static let radius: CGFloat = 24
    static let radiusMd: CGFloat = 22
    static let radiusSm: CGFloat = 20

    static let fadeUp: Animation = .easeOut(duration: 0.5)
    static let viewTransition: Animation = .easeOut(duration: 0.45)
    static let gentleBounce: Animation = .easeInOut(duration: 2).repeatForever(autoreverses: true)

    enum FontName {
        static let regular  = "IBMPlexMono-Regular"
        static let medium   = "IBMPlexMono-Medium"
        static let semibold = "IBMPlexMono-SemiBold"
        static let bold     = "IBMPlexMono-Bold"

        static func name(for weight: SwiftUI.Font.Weight) -> String {
            switch weight {
            case .medium: return medium
            case .semibold: return semibold
            case .bold, .heavy, .black: return bold
            default: return regular
            }
        }
    }

    enum Fonts {
        static func mono(_ size: CGFloat, weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font {
            .custom(FontName.name(for: weight), size: size)
        }
    }
}

// MARK: - Color hex init

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

// MARK: - SKColor hex + blend

extension SKColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255
        let g = CGFloat((hex >> 8) & 0xFF) / 255
        let b = CGFloat(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: alpha)
    }

    func blended(to other: SKColor, fraction: CGFloat) -> SKColor {
        let f = max(0, min(1, fraction))
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        #if canImport(UIKit)
        self.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        #else
        let c1 = self.usingColorSpace(.sRGB) ?? self
        let c2 = other.usingColorSpace(.sRGB) ?? other
        c1.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        c2.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        #endif
        return SKColor(
            red:   r1 + (r2 - r1) * f,
            green: g1 + (g2 - g1) * f,
            blue:  b1 + (b2 - b1) * f,
            alpha: a1 + (a2 - a1) * f
        )
    }
}

// MARK: - SpriteKit palette bridge

enum SKPalette {
    static func from(_ p: Theme.Palette) -> Colors { Colors(palette: p) }

    struct Colors {
        let palette: Theme.Palette
        var background: SKColor        { palette.background.sk }
        var surface: SKColor           { palette.surface.sk }
        var primary: SKColor           { palette.primary.sk }
        var accent: SKColor            { palette.accent.sk }
        var launcher: SKColor          { palette.launcher.sk }
        var pickup: SKColor            { palette.pickup.sk }
        var textPrimary: SKColor       { palette.textPrimary.sk }
        var textSecondary: SKColor     { palette.textSecondary.sk }
        var border: SKColor            { palette.border.sk }
        var destructive: SKColor       { palette.destructive.sk }
        var glow: SKColor              { palette.glow.sk }
    }
}

extension Color {
    var sk: SKColor { SKColor(self) }
}
