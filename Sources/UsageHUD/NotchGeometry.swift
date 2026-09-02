import CoreGraphics
import Foundation

/// Layout math for the notch shelf.
///
/// Everything here works on plain rectangles in AppKit screen coordinates
/// (bottom-left origin, y growing upward) so it can be exercised in tests
/// without a real display attached.
enum NotchGeometry {
    /// Displays without a camera housing get a notch-shaped hot zone of this
    /// width at the top centre so the feature still works on them.
    static let virtualNotchWidth: CGFloat = 200
    /// Used when a display reports no menu bar height at all.
    static let fallbackMenuBarHeight: CGFloat = 24

    // The tray: a row of provider rings hanging under the notch.
    static let ringDiameter: CGFloat = 35
    static let percentHeight: CGFloat = 13
    static let ringToPercentGap: CGFloat = 6
    static let tileWidth: CGFloat = 46
    static let tileSpacing: CGFloat = 6
    static let trayHorizontalPadding: CGFloat = 14
    static let trayTopPadding: CGFloat = 10
    static let trayBottomPadding: CGFloat = 12
    static let trayBottomRadius: CGFloat = 24
    /// Outward flare where the tray meets the screen edge.
    static let trayTopRadius: CGFloat = 11

    // The collapsed shape. Drawn a little wider than the camera housing so its
    // own curves stay visible beside the hardware's, and kept gently rounded
    // so opening grows the curves instead of conjuring them.
    static let closedOverhang: CGFloat = 2
    static let closedTopRadius: CGFloat = 5
    static let closedBottomRadius: CGFloat = 12
    /// How much the closed shape swells while the pointer waits in the hot
    /// zone: the acknowledgement that something is about to open.
    static let peekWidthGrowth: CGFloat = 14
    static let peekHeightGrowth: CGFloat = 5
    /// A floor so a lone ring still gets a shape wide enough to feel like a
    /// tray rather than a bump. Kept close to the hardware notch width so the
    /// tray reads as an extension of it rather than a panel parked underneath.
    static let minimumExpandedWidth: CGFloat = 232

    // The detail: hovering swaps the tray's content — the hovered ring glides
    // to the left edge and bars unfold in the space the other rings vacate.
    // The shape itself never resizes once open, so the silhouette is a
    // constant and only the contents are liquid.
    static let detailTileWidth: CGFloat = 208
    /// Gap between the ring column and the bars that unfold beside it.
    static let detailInnerSpacing: CGFloat = 12

    static let hotZoneInset: CGFloat = 6
    static let hotZoneDrop: CGFloat = 2
    /// `CGRect.contains` excludes maxY, and the notch's maxY is the top of the
    /// screen — which is exactly where the cursor parks when you throw it at
    /// the notch. Overshoot off-screen so that edge counts as a hit.
    static let hotZoneTopOvershoot: CGFloat = 4
    static let stayZoneSlack: CGFloat = 10
    /// Room left around the tray inside the window so its shadow can render.
    /// Must comfortably exceed the tray's shadow blur: a shadow that is still
    /// visible where the window ends gets cut off in a hard-edged rectangle.
    static let shadowPadding: CGFloat = 40

    static var tileHeight: CGFloat { ringDiameter + ringToPercentGap + percentHeight }

    struct Notch: Equatable {
        /// The notch (or its stand-in) in screen coordinates.
        var rect: CGRect
        /// `false` when we synthesised the rect because the display has no
        /// camera housing.
        var isHardware: Bool

        var width: CGFloat { rect.width }
        var height: CGFloat { rect.height }
    }

    /// Resolves the notch rect for one display.
    ///
    /// `auxiliaryLeftWidth`/`auxiliaryRightWidth` are the menu bar strips either
    /// side of the camera housing; the gap between them is the notch itself.
    static func notch(
        screenFrame: CGRect,
        safeAreaTop: CGFloat,
        auxiliaryLeftWidth: CGFloat?,
        auxiliaryRightWidth: CGFloat?,
        menuBarHeight: CGFloat
    ) -> Notch {
        if
            safeAreaTop > 0,
            let left = auxiliaryLeftWidth,
            let right = auxiliaryRightWidth
        {
            let width = screenFrame.width - left - right
            if width > 0 {
                return Notch(
                    rect: CGRect(
                        x: screenFrame.minX + left,
                        y: screenFrame.maxY - safeAreaTop,
                        width: width,
                        height: safeAreaTop
                    ),
                    isHardware: true
                )
            }
        }

        let height = menuBarHeight > 0 ? menuBarHeight : fallbackMenuBarHeight
        let width = min(virtualNotchWidth, screenFrame.width)
        return Notch(
            rect: CGRect(
                x: screenFrame.midX - width / 2,
                y: screenFrame.maxY - height,
                width: width,
                height: height
            ),
            isHardware: false
        )
    }

    /// The one width every open state shares. Sized for whichever needs more
    /// room — the ring row or the swapped-in detail — so hovering never makes
    /// the shape breathe.
    static func expandedWidth(notch: Notch, providerCount: Int, theme: NotchTheme = .classic) -> CGFloat {
        max(max(notch.width, theme.contentWidth(providerCount: providerCount)), minimumExpandedWidth)
    }

    /// Height of the ring row, excluding the notch strip it hangs from. The
    /// tray never grows downward past this, whatever is hovered.
    static var trayHeight: CGFloat {
        trayTopPadding + tileHeight + trayBottomPadding
    }

    /// The same, for whichever tray design is selected.
    static func trayHeight(for theme: NotchTheme) -> CGFloat {
        theme.trayHeight
    }

    /// The shelf at rest: notch strip plus the ring row.
    static func shelfBounds(notch: Notch, providerCount: Int, theme: NotchTheme = .classic) -> CGRect {
        let width = expandedWidth(notch: notch, providerCount: providerCount, theme: theme)
        let height = notch.height + trayHeight(for: theme)
        return CGRect(
            x: notch.rect.midX - width / 2,
            y: notch.rect.maxY - height,
            width: width,
            height: height
        )
    }

    /// The window frame. It stays this size in every state so SwiftUI animates
    /// the shape without the window resizing, plus room for the shadow. The
    /// top edge stays flush with the screen, where there is nothing to cast
    /// onto.
    static func panelFrame(notch: Notch, providerCount: Int, theme: NotchTheme = .classic) -> CGRect {
        let bounds = shelfBounds(notch: notch, providerCount: providerCount, theme: theme)
        let width = bounds.width + shadowPadding * 2
        let height = bounds.height + shadowPadding
        return CGRect(
            x: bounds.midX - width / 2,
            y: bounds.maxY - height,
            width: width,
            height: height
        )
    }

    /// Where the pointer has to land to pull the tray down.
    static func hotZone(notch: Notch) -> CGRect {
        CGRect(
            x: notch.rect.minX - hotZoneInset,
            y: notch.rect.minY - hotZoneDrop,
            width: notch.rect.width + hotZoneInset * 2,
            height: notch.rect.height + hotZoneDrop + hotZoneTopOvershoot
        )
    }

    /// Where the pointer may roam without the tray retracting. Wider than the
    /// tray so a shaky hand at its edge does not flap the animation. The tray
    /// never grows past its shelf in any state, so slack is all it needs.
    static func stayZone(shelfBounds: CGRect) -> CGRect {
        CGRect(
            x: shelfBounds.minX - stayZoneSlack,
            y: shelfBounds.minY - stayZoneSlack,
            width: shelfBounds.width + stayZoneSlack * 2,
            height: shelfBounds.height + stayZoneSlack * 2
        )
    }
}
