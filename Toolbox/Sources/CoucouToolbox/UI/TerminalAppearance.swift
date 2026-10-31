import AppKit
import SwiftTerm

/// Terminal colors tuned for Cyclop's dark notch panel.
enum TerminalAppearance {
    /// Sixteen ANSI colors: dark 0–7, bright 8–15.
    static func palette() -> [Color] {
        [
            rgb(30, 30, 46),    // black
            rgb(243, 139, 168), // red
            rgb(166, 227, 161), // green
            rgb(249, 226, 175), // yellow
            rgb(137, 180, 250), // blue
            rgb(203, 166, 247), // magenta
            rgb(148, 226, 213), // cyan
            rgb(205, 214, 244), // white
            rgb(88, 91, 112),   // bright black
            rgb(243, 139, 168), // bright red
            rgb(166, 227, 161), // bright green
            rgb(249, 226, 175), // bright yellow
            rgb(137, 180, 250), // bright blue
            rgb(203, 166, 247), // bright magenta
            rgb(148, 226, 213), // bright cyan
            rgb(255, 255, 255), // bright white
        ]
    }

    static func apply(to view: TerminalView) {
        view.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        view.nativeForegroundColor = NSColor(white: 1, alpha: 0.85)
        view.nativeBackgroundColor = NSColor(white: 0, alpha: 0.35)
        view.caretColor = NSColor(white: 1, alpha: 0.92)
        view.selectedTextBackgroundColor = NSColor(white: 1, alpha: 0.22)
        view.installColors(palette())
    }

    private static func rgb(_ red: UInt16, _ green: UInt16, _ blue: UInt16) -> Color {
        Color(red: red * 257, green: green * 257, blue: blue * 257)
    }
}
