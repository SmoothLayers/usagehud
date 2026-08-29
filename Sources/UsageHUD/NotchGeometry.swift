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
    static let ringDiameter: CGFloat = 38
    static let percentHeight: CGFloat = 14
    static let ringToPercentGap: CGFloat = 5
    static let tileWidth: CGFloat = 54
    static let tileSpacing: CGFloat = 10
    static let trayHorizontalPadding: CGFloat = 16
    static let trayTopPadding: CGFloat = 10
    static let trayBottomPadding: CGFloat = 12
    static let trayBottomRadius: CGFloat = 26
    /// Outward flare where the tray meets the screen edge.
    static let trayTopRadius: CGFloat = 11
    /// Keeps the panel from breathing sideways when the detail opens: both
    /// states share one width, so only the height animates on hover.
    static let minimumExpandedWidth: CGFloat = 248

    // The detail section, which grows inside the same shape on hover rather
    // than floating beside it.
    static let detailHorizontalPadding: CGFloat = 16
    static let detailTopPadding: CGFloat = 4
    static let detailBottomPadding: CGFloat = 14
    static let detailHeaderHeight: CGFloat = 18
    static let detailRowHeight: CGFloat = 34
    static let detailSpacing: CGFloat = 8
    static let detailDividerInset: CGFloat = 14

    static let hotZoneInset: CGFloat = 6
    static let hotZoneDrop: CGFloat = 2
    /// `CGRect.contains` excludes maxY, and the notch's maxY is the top of the
    /// screen — which is exactly where the cursor parks when you throw it at
    /// the notch. Overshoot off-screen so that edge counts as a hit.
    static let hotZoneTopOvershoot: CGFloat = 4
    static let stayZoneSlack: CGFloat = 10
    /// Room left around the tray inside the window so its shadow can render.
    static let shadowPadding: CGFloat = 26

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

    /// Width shared by every expanded state.
    static func expandedWidth(notch: Notch, providerCount: Int) -> CGFloat {
        let count = max(1, providerCount)
        let trayContent = trayHorizontalPadding * 2
            + tileWidth * CGFloat(count)
            + tileSpacing * CGFloat(count - 1)
        return max(max(notch.width, trayContent), minimumExpandedWidth)
    }

    /// Height of the ring row, excluding the notch strip it hangs from.
    static var trayHeight: CGFloat {
        trayTopPadding + tileHeight + trayBottomPadding
    }

    /// Height the detail section adds when a ring is hovered.
    static func detailHeight(windowCount: Int) -> CGFloat {
        let count = max(1, windowCount)
        return detailTopPadding
            + detailHeaderHeight
            + detailSpacing
            + detailRowHeight * CGFloat(count)
            + detailSpacing * CGFloat(count - 1)
            + detailBottomPadding
    }

    /// The shelf at rest: notch strip plus the ring row.
    static func shelfBounds(notch: Notch, providerCount: Int) -> CGRect {
        let width = expandedWidth(notch: notch, providerCount: providerCount)
        let height = notch.height + trayHeight
        return CGRect(
            x: notch.rect.midX - width / 2,
            y: notch.rect.maxY - height,
            width: width,
            height: height
        )
    }

    /// The window frame. It stays this size in every state so SwiftUI animates
    /// the shape without the window resizing, sized for the tallest the panel
    /// can get plus room for its shadow. The top edge stays flush with the
    /// screen, where there is nothing to cast onto.
    static func panelFrame(notch: Notch, providerCount: Int) -> CGRect {
        let bounds = shelfBounds(notch: notch, providerCount: providerCount)
        let width = bounds.width + shadowPadding * 2
        let height = bounds.height + detailHeight(windowCount: 2) + shadowPadding
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
    /// tray so a shaky hand at its edge does not flap the animation, and deep
    /// enough to cover the detail section once it has grown.
    static func stayZone(shelfBounds: CGRect) -> CGRect {
        let extraDepth = detailHeight(windowCount: 2)
        return CGRect(
            x: shelfBounds.minX - stayZoneSlack,
            y: shelfBounds.minY - stayZoneSlack - extraDepth,
            width: shelfBounds.width + stayZoneSlack * 2,
            height: shelfBounds.height + stayZoneSlack * 2 + extraDepth
        )
    }
}
