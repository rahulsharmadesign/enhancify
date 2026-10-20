import AppKit
import SwiftUI

/// Semantic color tokens for every Enhancify surface.
///
/// Haze paint: canvas, translucent panel/surface, surface-2 pills/wells,
/// surface-3 pressed, hairline strokes, 3-level text, accent + soft washes,
/// ok/warn/bad, 170° panel and accent gradients, 3px focus glow.
/// This is the only file in the app allowed to hold a raw color literal.
enum EnhancifyColor {

    /// Light/dark plus Increase Contrast. Named colors consult this so
    /// hairlines and wells stay readable on macOS 27 Liquid Glass (intensity
    /// slider + Increase Contrast) without a second glass lens.
    struct DisplayTraits: Equatable {
        var isDark: Bool
        var isHighContrast: Bool

        static func resolve(_ appearance: NSAppearance) -> DisplayTraits {
            // macOS 27 collapsed high-contrast into a system switch. Named
            // high-contrast appearances no longer survive `bestMatch` — they
            // resolve as Aqua / Dark Aqua. Read the workspace flag instead.
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let isHighContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            return DisplayTraits(isDark: isDark, isHighContrast: isHighContrast)
        }
    }

    // MARK: - Surfaces

    /// Page fill. Haze `--canvas`: #F2F3F6 light, #141517 dark.
    static let canvasNSColor = NSColor(name: "EnhancifyCanvas") { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return dark
            ? NSColor(srgbRed: 20 / 255, green: 21 / 255, blue: 23 / 255, alpha: 1)
            : NSColor(srgbRed: 242 / 255, green: 243 / 255, blue: 246 / 255, alpha: 1)
    }

    /// Composer field fill on the glass slab. Dark: 8% white so the well
    /// sits in the slab instead of reading as a second card. Light: 55%
    /// white so the caret still has a well, not a bright plate.
    /// Reduce Transparency uses `panelSolid` instead (see `GlassModule`).
    static var composerWell: Color {
        Color(nsColor: NSColor(name: "EnhancifyComposerWell") { appearance in
            let traits = DisplayTraits.resolve(appearance)
            if traits.isDark {
                return NSColor.white.withAlphaComponent(traits.isHighContrast ? 0.16 : 0.08)
            }
            return NSColor.white.withAlphaComponent(traits.isHighContrast ? 0.78 : 0.55)
        })
    }
    /// Opaque plate for Reduce Transparency. Haze `--panel-solid`:
    /// #FFFFFF light, #202124 dark.
    static let panelSolidNSColor = NSColor(name: "EnhancifyPanelSolid") { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return dark
            ? NSColor(srgbRed: 32 / 255, green: 33 / 255, blue: 36 / 255, alpha: 1)
            : .white
    }

    static var canvas: Color { Color(nsColor: canvasNSColor) }
    static var panelSolid: Color { Color(nsColor: panelSolidNSColor) }

    /// Scrim tint for the clear-glass window slab. The glass style carries the
    /// refraction; this decides how much of the desktop shows through. Dark
    /// gets a near-black wash, light a soft white — both strong enough that a
    /// busy background never competes with the panel's type, light enough that
    /// the glass edge and bending still read. `NSGlassEffectView.tintColor`
    /// expects an NSColor; the SwiftUI side never draws this.
    static let glassTintNSColor = NSColor(name: "EnhancifyGlassTint") { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return dark
            ? NSColor.black.withAlphaComponent(0.28)
            : NSColor.white.withAlphaComponent(0.50)
    }

    /// SwiftUI twin of the slab tint, for surfaces that sit on the system's own
    /// material rather than an `NSGlassEffectView` — the menu bar dropdown.
    /// Lighter than `glassTintNSColor`: the system material is already partly
    /// opaque there, and matching the slab's full strength double-darkened it.
    static var glassScrim: Color { Color(nsColor: glassScrimNSColor) }

    static let glassScrimNSColor = NSColor(name: "EnhancifyGlassScrim") { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return dark
            ? NSColor.black.withAlphaComponent(0.16)
            : NSColor.white.withAlphaComponent(0.30)
    }
    /// Translucent card fill. Haze `--surface`: white 72% light. Dark is 10%
    /// white, up from 5%: the panel slab switched to clear glass, and a 5%
    /// wash over it left markdown floating on the refraction.
    static var surface: Color {
        Color(nsColor: NSColor(name: "EnhancifySurface") { appearance in
            let traits = DisplayTraits.resolve(appearance)
            if traits.isDark {
                return NSColor.white.withAlphaComponent(traits.isHighContrast ? 0.16 : 0.10)
            }
            return NSColor.white.withAlphaComponent(traits.isHighContrast ? 0.88 : 0.72)
        })
    }
    /// Pill / well fill. Haze `--surface-2`: #F3F4F7 light, white 7% dark.
    static var surface2: Color {
        Color(nsColor: NSColor(name: "EnhancifySurface2") { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return dark
                ? NSColor.white.withAlphaComponent(0.07)
                : NSColor(srgbRed: 243 / 255, green: 244 / 255, blue: 247 / 255, alpha: 1)
        })
    }
    /// Pressed fill. Haze `--surface-3`: #E9EBF0 light, white 11% dark.
    static var surface3: Color {
        Color(nsColor: NSColor(name: "EnhancifySurface3") { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return dark
                ? NSColor.white.withAlphaComponent(0.11)
                : NSColor(srgbRed: 233 / 255, green: 235 / 255, blue: 240 / 255, alpha: 1)
        })
    }
    /// System text-field well. Settings sits on window material; filling
    /// editors with `canvas` painted a navy patch next to native Name/Icon fields.
    static var input: Color { Color(nsColor: .textBackgroundColor) }

    // MARK: - Lines

    /// Hairline stroke. Haze `--hair`: ink 7% light, white 8% dark.
    static var border: Color {
        Color(nsColor: NSColor(name: "EnhancifyHair") { appearance in
            let traits = DisplayTraits.resolve(appearance)
            if traits.isDark {
                return NSColor.white.withAlphaComponent(traits.isHighContrast ? 0.32 : 0.08)
            }
            return NSColor(srgbRed: 17 / 255, green: 20 / 255, blue: 24 / 255, alpha: traits.isHighContrast ? 0.28 : 0.07)
        })
    }
    /// Only where a hairline must survive against a busy fill.
    /// Haze `--hair-strong`: ink 12% light, white 14% dark.
    static var strongBorder: Color {
        Color(nsColor: NSColor(name: "EnhancifyHairStrong") { appearance in
            let traits = DisplayTraits.resolve(appearance)
            if traits.isDark {
                return NSColor.white.withAlphaComponent(traits.isHighContrast ? 0.45 : 0.14)
            }
            return NSColor(srgbRed: 17 / 255, green: 20 / 255, blue: 24 / 255, alpha: traits.isHighContrast ? 0.40 : 0.12)
        })
    }
    /// Lit 1pt along the top edge. Haze `--edge`.
    static var edge: Color {
        Color(nsColor: NSColor(name: "EnhancifyEdge") { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return dark
                ? NSColor.white.withAlphaComponent(0.06)
                : NSColor.white.withAlphaComponent(0.90)
        })
    }

    // MARK: - Text

    /// Haze `--text`: #14171C light, #ECEDEF dark.
    static var textPrimary: Color {
        Color(nsColor: NSColor(name: "EnhancifyText") { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return dark
                ? NSColor(srgbRed: 236 / 255, green: 237 / 255, blue: 239 / 255, alpha: 1)
                : NSColor(srgbRed: 20 / 255, green: 23 / 255, blue: 28 / 255, alpha: 1)
        })
    }
    /// Haze `--text-2`: #6B7280 light, #A3A7AF dark.
    static var textSecondary: Color {
        Color(nsColor: NSColor(name: "EnhancifyText2") { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return dark
                ? NSColor(srgbRed: 163 / 255, green: 167 / 255, blue: 175 / 255, alpha: 1)
                : NSColor(srgbRed: 107 / 255, green: 114 / 255, blue: 128 / 255, alpha: 1)
        })
    }
    /// Haze `--text-3`: #A0A6B1 light, #6E737C dark.
    static var textTertiary: Color {
        Color(nsColor: NSColor(name: "EnhancifyText3") { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return dark
                ? NSColor(srgbRed: 110 / 255, green: 115 / 255, blue: 124 / 255, alpha: 1)
                : NSColor(srgbRed: 160 / 255, green: 166 / 255, blue: 177 / 255, alpha: 1)
        })
    }
    /// Status-item mark. Black in Light, white in Dark. Baked as `.original`
    /// so wallpaper-tinted menu bars cannot invert a template glyph.
    static let menuBarGlyphNSColor = NSColor(name: "EnhancifyMenuBarGlyph") { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return dark ? .white : .black
    }
    static var menuBarGlyph: Color { Color(nsColor: menuBarGlyphNSColor) }

    /// Links in Settings. System link color so
    /// it stays a distinct hue from `textPrimary` in both appearances.
    static var link: Color { Color(nsColor: .linkColor) }

    // MARK: - Accent

    @MainActor
    static var accent: Color {
        (PrimaryColor(rawValue: SettingsStore.shared.primaryColorID) ?? .violet).color
    }
    /// AppKit surfaces that cannot read the store on the main actor, such as a
    /// window's own background.
    static var accentNSColor: NSColor { PrimaryColor.selected.nsColor }
    /// Label color on top of `accent`. Reads from the selected primary rather
    /// than assuming indigo, so a lighter accent can pair with dark glyphs.
    @MainActor
    static var onAccent: Color {
        (PrimaryColor(rawValue: SettingsStore.shared.primaryColorID) ?? .violet).selectedForeground
    }

    // MARK: - States

    static var badge: Color { surface2 }
    static var hoverFill: Color { surface3 }
    /// A filled control that is currently unavailable, such as the panel's send
    /// button before an instruction is typed.
    static var disabledFill: Color { surface3 }
    /// Barely-there fill that separates a control from the card behind it
    /// without reading as a button, used by the composer's picker pills.
    /// Haze `--surface-2`.
    static var subtleFill: Color { surface2 }
    /// Grouped settings card. Haze `--surface`.
    static var card: Color { surface }
    /// Haze `--ok`: #22A06B light, #3DCB8A dark.
    static var positive: Color {
        Color(nsColor: NSColor(name: "EnhancifyOk") { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return dark
                ? NSColor(srgbRed: 61 / 255, green: 203 / 255, blue: 138 / 255, alpha: 1)
                : NSColor(srgbRed: 34 / 255, green: 160 / 255, blue: 107 / 255, alpha: 1)
        })
    }
    /// Haze `--warn`: #E0A100 light, #F2B933 dark.
    static var warning: Color {
        Color(nsColor: NSColor(name: "EnhancifyWarn") { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return dark
                ? NSColor(srgbRed: 242 / 255, green: 185 / 255, blue: 51 / 255, alpha: 1)
                : NSColor(srgbRed: 224 / 255, green: 161 / 255, blue: 0, alpha: 1)
        })
    }
    /// Haze `--bad`: #E5484D light, #F26B6F dark.
    static var destructive: Color {
        Color(nsColor: NSColor(name: "EnhancifyBad") { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return dark
                ? NSColor(srgbRed: 242 / 255, green: 107 / 255, blue: 111 / 255, alpha: 1)
                : NSColor(srgbRed: 229 / 255, green: 72 / 255, blue: 77 / 255, alpha: 1)
        })
    }
    /// Danger well fill behind destructive settings groups.
    /// Haze `--bad-soft`: bad 8% light, bad 14% dark.
    static var dangerFill: Color {
        Color(nsColor: NSColor(name: "EnhancifyBadSoft") { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return dark
                ? NSColor(srgbRed: 242 / 255, green: 107 / 255, blue: 111 / 255, alpha: 0.14)
                : NSColor(srgbRed: 229 / 255, green: 72 / 255, blue: 77 / 255, alpha: 0.08)
        })
    }
    /// Hairline for the danger well. Haze `--bad-hair`: bad 22% light, bad 30% dark.
    static var dangerBorder: Color {
        Color(nsColor: NSColor(name: "EnhancifyBadHair") { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return dark
                ? NSColor(srgbRed: 242 / 255, green: 107 / 255, blue: 111 / 255, alpha: 0.30)
                : NSColor(srgbRed: 229 / 255, green: 72 / 255, blue: 77 / 255, alpha: 0.22)
        })
    }

    /// 170° primary fill for pills and the send disc. Haze `--g-accent`.
    @MainActor
    static var accentGradient: LinearGradient {
        let base = accent
        let top = Color(nsColor: accentNSColor.blended(withFraction: 0.18, of: .white) ?? accentNSColor)
        return LinearGradient(
            colors: [top, base],
            startPoint: UnitPoint(x: 0.42, y: 0),
            endPoint: UnitPoint(x: 0.58, y: 1)
        )
    }

    /// Soft 3pt halo used as the focus ring. Haze `--glow`.
    @MainActor
    static var focusGlow: Color { accent.opacity(0.14) }

    /// The panel's close disc, drawn in AppKit. Fixed rather than dynamic: this
    /// is the traffic-light red users expect in a window corner, and it has to
    /// read the same over whatever the panel is floating above.
    enum CloseDisc {
        static let fill = NSColor(srgbRed: 1, green: 0.37, blue: 0.34, alpha: 1)
        static let pressedFill = NSColor(srgbRed: 0.78, green: 0.16, blue: 0.14, alpha: 1)
        static let glyph = NSColor(srgbRed: 0.30, green: 0.04, blue: 0.03, alpha: 0.88)
    }

    // MARK: - Elevation

    static let softShadow = Color.black.opacity(0.075)

    /// Haze e2 lift for floating cards (menus, popups): soft lift plus a tight
    /// contact shadow. Window slabs use `softShadow` instead.
    static var liftShadow: Color {
        Color(nsColor: NSColor(name: "EnhancifyLift") { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor.black.withAlphaComponent(dark ? 0.35 : 0.06)
        })
    }

    static var contactShadow: Color {
        Color(nsColor: NSColor(name: "EnhancifyContact") { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor.black.withAlphaComponent(dark ? 0.30 : 0.04)
        })
    }
}
