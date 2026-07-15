import SwiftUI

enum CompactLayout: String, CaseIterable {
    case vertical
    case horizontal
}

enum HUDAccentPalette {
    static let choices = ["54E8BA", "63C5FF", "A78BFA", "F6C85F", "F59363", "FF6B81"]
    static let codexDefault = "54E8BA"
    static let claudeDefault = "F59363"
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
