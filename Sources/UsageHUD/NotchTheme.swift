import CoreGraphics
import Foundation

/// Which design the notch tray draws its provider readout in.
///
/// Every theme shares the shell — the black shape hanging off the housing,
/// its rim, shadow, peek and sheen — and swaps only the content inside it.
/// Each one also declares the room it needs, so the panel and hot zones are
/// sized for the design that is actually on screen.
enum NotchTheme: String, CaseIterable, Identifiable {
    case classic
    case instrument
    case capsule
    case concentric
    case ledger
    case segmented

    var id: String { rawValue }

    /// Short label for the settings picker.
    var title: String {
        switch self {
        case .classic: return "CLASSIC"
        case .instrument: return "INSTRUMENT"
        case .capsule: return "CAPSULE"
        case .concentric: return "CONCENTRIC"
        case .ledger: return "LEDGER"
        case .segmented: return "SEGMENTED"
        }
    }

    /// One line under the picker describing the selected design.
    var blurb: String {
        switch self {
        case .classic: return "Rings with a glowing arc and the percent beneath"
        case .instrument: return "Hairline dials on a tick track, monospaced figures"
        case .capsule: return "Glass pills; the hovered one swallows the row"
        case .concentric: return "One gauge of nested arcs with a legend beside it"
        case .ledger: return "No rings: large figures in hairline columns"
        case .segmented: return "Rings of discrete cells that light up one by one"
        }
    }

    /// Height of the tray below the notch strip, paddings included. Constant
    /// per theme so the shape never breathes when the content swaps.
    var trayHeight: CGFloat {
        switch self {
        case .classic:
            return NotchGeometry.trayTopPadding + NotchGeometry.tileHeight + NotchGeometry.trayBottomPadding
        case .instrument: return 90
        case .capsule: return 56
        case .concentric: return 88
        case .ledger: return 72
        case .segmented: return 80
        }
    }

    /// Width the tray content needs, paddings included, sized for whichever
    /// of the row or the detail is wider.
    func contentWidth(providerCount: Int) -> CGFloat {
        let count = CGFloat(max(1, providerCount))
        switch self {
        case .classic:
            let row = NotchGeometry.trayHorizontalPadding * 2
                + NotchGeometry.tileWidth * count
                + NotchGeometry.tileSpacing * (count - 1)
            let detail = NotchGeometry.trayHorizontalPadding * 2 + NotchGeometry.detailTileWidth
            return max(row, detail)
        case .instrument, .segmented:
            let row = 28 + 58 * count + 4 * (count - 1)
            return max(row, 270)
        case .capsule:
            return 24 + 92 * count + 6 * (count - 1)
        case .concentric:
            return 260
        case .ledger:
            return 28 + 96 * count
        }
    }
}
