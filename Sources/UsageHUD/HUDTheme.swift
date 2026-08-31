import SwiftUI

enum CompactLayout: String, CaseIterable {
    case vertical
    case horizontal
}

enum HUDAccentPalette {
    static let choices = ["2EF2A9", "3FB6FF", "9B6DFF", "FFC83D", "FF8A4A", "FF5674"]
    static let codexDefault = "2EF2A9"
    static let claudeDefault = "FF8A4A"
    static let kimiDefault = "9B6DFF"

    /// Hues from the pre-vibrancy palette, mapped onto their successors so a
    /// saved pick keeps its colour instead of resetting to the default.
    private static let legacy = [
        "54E8BA": "2EF2A9",
        "63C5FF": "3FB6FF",
        "A78BFA": "9B6DFF",
        "F6C85F": "FFC83D",
        "F59363": "FF8A4A",
        "FF6B81": "FF5674"
    ]

    static func normalized(_ hex: String) -> String {
        legacy[hex] ?? hex
    }
}

extension Color {
    init(hudHex hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
