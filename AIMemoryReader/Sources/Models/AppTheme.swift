import SwiftUI

/// User-selectable visual theme.
/// - `.standard`  → current look, follows system light/dark.
/// - `.eyeCare`   → Solarized-based palette tuned for long reading sessions.
enum AppTheme: String, CaseIterable, Identifiable, Sendable {
    case standard
    case eyeCare

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .eyeCare:  return "Eye Care"
        }
    }

    var iconName: String {
        switch self {
        case .standard: return "circle.lefthalf.filled"
        case .eyeCare:  return "leaf.fill"
        }
    }

    var menuDescription: String {
        switch self {
        case .standard: return "Standard (System)"
        case .eyeCare:  return "Eye Care (Solarized)"
        }
    }
}

// MARK: - Solarized palette
// Reference: https://ethanschoonover.com/solarized/
// Widely used in VS Code / iTerm2 / vim for eye-friendly long-form reading.

private enum Solarized {
    // Backgrounds & text tones
    static let base03 = Color(red: 0 / 255,   green: 43 / 255,  blue: 54 / 255)   // darkest bg
    static let base02 = Color(red: 7 / 255,   green: 54 / 255,  blue: 66 / 255)
    static let base01 = Color(red: 88 / 255,  green: 110 / 255, blue: 117 / 255)  // emphasized
    static let base00 = Color(red: 101 / 255, green: 123 / 255, blue: 131 / 255)  // body (light)
    static let base0  = Color(red: 131 / 255, green: 148 / 255, blue: 150 / 255)  // body (dark)
    static let base1  = Color(red: 147 / 255, green: 161 / 255, blue: 161 / 255)
    static let base2  = Color(red: 238 / 255, green: 232 / 255, blue: 213 / 255)  // secondary bg
    static let base3  = Color(red: 253 / 255, green: 246 / 255, blue: 227 / 255)  // brightest bg

    // Accents
    static let yellow  = Color(red: 181 / 255, green: 137 / 255, blue: 0 / 255)
    static let orange  = Color(red: 203 / 255, green: 75 / 255,  blue: 22 / 255)
    static let red     = Color(red: 220 / 255, green: 50 / 255,  blue: 47 / 255)
    static let magenta = Color(red: 211 / 255, green: 54 / 255,  blue: 130 / 255)
    static let violet  = Color(red: 108 / 255, green: 113 / 255, blue: 196 / 255)
    static let blue    = Color(red: 38 / 255,  green: 139 / 255, blue: 210 / 255)
    static let cyan    = Color(red: 42 / 255,  green: 161 / 255, blue: 152 / 255)
    static let green   = Color(red: 133 / 255, green: 153 / 255, blue: 0 / 255)
}

// MARK: - ThemePalette

/// Colors used across reading UI. Resolved per (theme, colorScheme).
struct ThemePalette: Sendable {
    let isEyeCare: Bool

    let background: Color
    let secondaryBackground: Color
    let sidebarBackground: Color
    let text: Color
    let secondaryText: Color
    let heading: Color
    let accent: Color
    let code: Color
    let codeBackground: Color
    let link: Color
    let blockquote: Color
    let divider: Color

    /// Highlight color for in-page find matches that are not the current focus.
    let findMatch: Color
    /// Highlight for the currently-focused find match.
    let findCurrent: Color

    static func resolve(_ theme: AppTheme, colorScheme: ColorScheme) -> ThemePalette {
        switch theme {
        case .standard:
            return colorScheme == .dark ? standardDark : standardLight
        case .eyeCare:
            return colorScheme == .dark ? solarizedDark : solarizedLight
        }
    }

    // MARK: Standard (semantic system colors — keep the original look)
    static let standardLight = ThemePalette(
        isEyeCare: false,
        background: Color.clear,            // use system default
        secondaryBackground: Color.clear,
        sidebarBackground: Color.clear,
        text: .primary,
        secondaryText: .secondary,
        heading: .primary,
        accent: .accentColor,
        code: .pink,
        codeBackground: Color.secondary.opacity(0.12),
        link: .accentColor,
        blockquote: .secondary,
        divider: Color.secondary.opacity(0.25),
        findMatch: Color.yellow.opacity(0.45),
        findCurrent: Color.orange.opacity(0.75)
    )

    static let standardDark = ThemePalette(
        isEyeCare: false,
        background: Color.clear,
        secondaryBackground: Color.clear,
        sidebarBackground: Color.clear,
        text: .primary,
        secondaryText: .secondary,
        heading: .primary,
        accent: .accentColor,
        code: .pink,
        codeBackground: Color.secondary.opacity(0.18),
        link: .accentColor,
        blockquote: .secondary,
        divider: Color.secondary.opacity(0.25),
        findMatch: Color.yellow.opacity(0.35),
        findCurrent: Color.orange.opacity(0.70)
    )

    // MARK: Eye-care (Solarized)
    static let solarizedLight = ThemePalette(
        isEyeCare: true,
        background: Solarized.base3,         // #FDF6E3
        secondaryBackground: Solarized.base2, // #EEE8D5
        sidebarBackground: Solarized.base2,
        text: Solarized.base00,              // #657B83
        secondaryText: Solarized.base01,     // #586E75
        heading: Solarized.base01,
        accent: Solarized.blue,
        code: Solarized.magenta,
        codeBackground: Solarized.base2.opacity(0.85),
        link: Solarized.blue,
        blockquote: Solarized.base01.opacity(0.85),
        divider: Solarized.base1.opacity(0.35),
        findMatch: Solarized.yellow.opacity(0.40),
        findCurrent: Solarized.orange.opacity(0.70)
    )

    static let solarizedDark = ThemePalette(
        isEyeCare: true,
        background: Solarized.base03,        // #002B36
        secondaryBackground: Solarized.base02,
        sidebarBackground: Solarized.base02,
        text: Solarized.base0,               // #839496
        secondaryText: Solarized.base1,
        heading: Solarized.base1,
        accent: Solarized.blue,
        code: Solarized.magenta,
        codeBackground: Solarized.base02.opacity(0.85),
        link: Solarized.blue,
        blockquote: Solarized.base1.opacity(0.85),
        divider: Solarized.base01.opacity(0.40),
        findMatch: Solarized.yellow.opacity(0.35),
        findCurrent: Solarized.orange.opacity(0.70)
    )
}

// MARK: - Environment access

private struct ThemePaletteKey: EnvironmentKey {
    static let defaultValue: ThemePalette = .standardLight
}

extension EnvironmentValues {
    var themePalette: ThemePalette {
        get { self[ThemePaletteKey.self] }
        set { self[ThemePaletteKey.self] = newValue }
    }
}
