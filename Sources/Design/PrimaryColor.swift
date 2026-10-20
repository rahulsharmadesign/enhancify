import AppKit
import SwiftUI

/// The twelve app-wide accent choices. Values are explicit sRGB so a future
/// Windows client can reproduce them exactly.
enum PrimaryColor: String, CaseIterable, Identifiable {
    case violet, indigo, blue, cyan, teal, emerald, green, lime, amber, orange, coral, rose

    static let storageKey = "primaryColorID"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .indigo: return "Indigo"
        case .violet: return "Violet"
        case .blue: return "Blue"
        case .cyan: return "Cyan"
        case .teal: return "Teal"
        case .emerald: return "Emerald"
        case .green: return "Green"
        case .lime: return "Lime"
        case .amber: return "Amber"
        case .orange: return "Orange"
        case .coral: return "Coral"
        case .rose: return "Rose"
        }
    }

    var color: Color {
        switch self {
        case .indigo: return Color(red: 0.420, green: 0.380, blue: 0.980)
        // The Enhancify brand purple (#7131E9), and the default accent.
        case .violet: return Color(red: 0.443, green: 0.192, blue: 0.914)
        case .blue: return Color(red: 0.090, green: 0.395, blue: 0.945)
        case .cyan: return Color(red: 0.015, green: 0.520, blue: 0.680)
        case .teal: return Color(red: 0.015, green: 0.480, blue: 0.470)
        case .emerald: return Color(red: 0.040, green: 0.500, blue: 0.290)
        case .green: return Color(red: 0.160, green: 0.540, blue: 0.140)
        case .lime: return Color(red: 0.340, green: 0.520, blue: 0.070)
        case .amber: return Color(red: 0.700, green: 0.400, blue: 0.020)
        case .orange: return Color(red: 0.780, green: 0.260, blue: 0.050)
        case .coral: return Color(red: 0.780, green: 0.200, blue: 0.180)
        case .rose: return Color(red: 0.865, green: 0.145, blue: 0.415)
        }
    }

    /// Active controls always use white glyphs and labels. Every shipped accent
    /// is intentionally dark enough for this pairing, avoiding
    /// appearance-transition-dependent black text.
    var selectedForeground: Color { .white }

    var nsColor: NSColor { NSColor(color) }

    static var selected: PrimaryColor {
        let stored = UserDefaults.standard.string(forKey: storageKey)
        return stored.flatMap(PrimaryColor.init(rawValue:)) ?? .violet
    }
}
