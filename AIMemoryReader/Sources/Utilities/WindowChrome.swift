#if os(macOS)
import AppKit
import SwiftUI

/// Tints the macOS window title bar to match the current app theme.
/// In Eye Care we paint the title bar with the Solarized secondary background
/// so the top of the window is visually consistent with the sidebar header.
@MainActor
enum WindowChrome {
    static func apply(for theme: AppTheme) {
        for window in NSApp.windows {
            apply(theme: theme, to: window)
        }
    }

    private static func apply(theme: AppTheme, to window: NSWindow) {
        switch theme {
        case .standard:
            // Restore system defaults.
            window.titlebarAppearsTransparent = false
            window.backgroundColor = .windowBackgroundColor
        case .eyeCare:
            // Solarized tone; the sidebar header sits right below this strip
            // so we want the two bars to read as one.
            window.titlebarAppearsTransparent = true
            window.backgroundColor = Self.eyeCareTitlebarColor(for: window)
        }
    }

    /// NSColor that tracks light/dark variants of Solarized base2/base02.
    private static func eyeCareTitlebarColor(for window: NSWindow) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            if isDark {
                return NSColor(red: 7 / 255.0, green: 54 / 255.0, blue: 66 / 255.0, alpha: 1.0)   // base02
            } else {
                return NSColor(red: 238 / 255.0, green: 232 / 255.0, blue: 213 / 255.0, alpha: 1.0) // base2
            }
        }
    }
}
#endif
