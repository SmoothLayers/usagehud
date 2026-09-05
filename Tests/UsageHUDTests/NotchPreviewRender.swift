// Preview exporter, not a visual regression test. Renders notch states
// for manual review. Skipped unless requested:
//   RENDER_NOTCH_PREVIEWS=1 swift test --filter NotchPreviewRender
import AppKit
import SwiftUI
import XCTest
@testable import UsageHUD

@MainActor
final class NotchPreviewRender: XCTestCase {
    func testRenderPreviews() throws {
        guard ProcessInfo.processInfo.environment["RENDER_NOTCH_PREVIEWS"] == "1" else {
            throw XCTSkip("preview rendering not requested")
        }

        let outputDir = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["NOTCH_PREVIEW_OUTPUT_DIR"] ?? "/tmp/notch-previews",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let suiteName = "notch-preview-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "showKimi")
        let settings = AppSettings(defaults: defaults)
        let store = UsageStore(defaults: defaults, settings: settings)
        let now = Date()
        store.codex = .loaded(ProviderUsage(
            kind: .codex,
            plan: "Pro",
            // A full window, so the droplet's disappearance at 100% is on film.
            primary: UsageWindow(label: "5h limit", usedPercent: 0, resetsAt: now.addingTimeInterval(9_360)),
            secondary: UsageWindow(label: "Weekly", usedPercent: 41, resetsAt: now.addingTimeInterval(300_000)),
            fetchedAt: now
        ))
        store.claude = .loaded(ProviderUsage(
            kind: .claude,
            plan: "Max",
            primary: UsageWindow(label: "Session", usedPercent: 63, resetsAt: now.addingTimeInterval(4_500)),
            secondary: UsageWindow(label: "Weekly", usedPercent: 22, resetsAt: now.addingTimeInterval(420_000)),
            fetchedAt: now
        ))
        store.kimi = .loaded(ProviderUsage(
            kind: .kimi,
            plan: nil,
            primary: UsageWindow(label: "Daily", usedPercent: 87, resetsAt: now.addingTimeInterval(52_000)),
            secondary: nil,
            fetchedAt: now
        ))

        let hardwareNotch = CGSize(width: 200, height: 32)

        func render(_ name: String, expanded: Bool, hovered: Int?, hardware: Bool, peeking: Bool = false) throws {
            let notch = NotchState()
            notch.isExpanded = expanded
            notch.isPeeking = peeking
            notch.notchSize = hardwareNotch
            notch.isHardwareNotch = hardware
            notch.hoveredIndex = hovered

            let metrics = NotchGeometry.Notch(
                rect: CGRect(origin: .zero, size: hardwareNotch),
                isHardware: hardware
            )
            let theme = settings.notchTheme
            let width = NotchGeometry.expandedWidth(notch: metrics, providerCount: 3, theme: theme)
                + NotchGeometry.shadowPadding * 2
            let height = hardwareNotch.height + theme.trayHeight + NotchGeometry.shadowPadding

            let view = ZStack(alignment: .top) {
                // Stand-in desktop so shadow and rim can be judged.
                LinearGradient(
                    colors: [
                        Color(red: 0.16, green: 0.19, blue: 0.30),
                        Color(red: 0.42, green: 0.26, blue: 0.35),
                        Color(red: 0.85, green: 0.51, blue: 0.34),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                NotchShelfView(store: store, settings: settings, notch: notch, openHUD: {})
            }
            .frame(width: width, height: height)

            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.nsImage, "could not render \(name)")
            let tiff = try XCTUnwrap(image.tiffRepresentation)
            let rep = try XCTUnwrap(NSBitmapImageRep(data: tiff))
            let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
            try png.write(to: outputDir.appendingPathComponent("\(name).png"))
        }

        try render("1-collapsed-virtual", expanded: false, hovered: nil, hardware: false)
        try render("2-peek", expanded: false, hovered: nil, hardware: true, peeking: true)
        try render("3-tray", expanded: true, hovered: nil, hardware: true)
        try render("4-detail-claude", expanded: true, hovered: 1, hardware: true)
        try render("5-detail-kimi", expanded: true, hovered: 2, hardware: true)

        // Every other tray design, at rest and with Claude's detail open.
        for theme in NotchTheme.allCases where theme != .classic {
            settings.setNotchTheme(theme)
            try render("7-\(theme.rawValue)-tray", expanded: true, hovered: nil, hardware: true)
            try render("8-\(theme.rawValue)-detail", expanded: true, hovered: 1, hardware: true)
        }
        settings.setNotchTheme(.classic)

        // One sheet of all six themes for the README, each shot captioned.
        try composeThemeSheet(in: outputDir)

        // Stale styling on film: the desaturated ring and the amber bead
        // under its number. Rendered last so the healthy shots above double
        // as the README's notch imagery.
        // The matte tray: black behind the icons, no glass and no floor light.
        settings.setNotchTrayDark(true)
        try render("9-dark-tray", expanded: true, hovered: nil, hardware: true)
        settings.setNotchTrayDark(false)

        store.claudeIsStale = true
        try render("6-tray-stale", expanded: true, hovered: nil, hardware: true)
        print("previews written to \(outputDir.path)")
    }

    /// Tiles the six theme shots into a three-column grid with a caption
    /// under each, so the README can show every tray design in one image.
    private func composeThemeSheet(in outputDir: URL) throws {
        let shots: [(NotchTheme, String)] = NotchTheme.allCases.map { theme in
            (theme, theme == .classic ? "3-tray" : "7-\(theme.rawValue)-tray")
        }
        let images = try shots.map { theme, name in
            let image = try XCTUnwrap(
                NSImage(contentsOf: outputDir.appendingPathComponent("\(name).png")),
                "missing preview \(name)"
            )
            return (theme, image)
        }

        let columns = 3
        let cellWidth: CGFloat = 640
        let cellHeight: CGFloat = 300
        let captionHeight: CGFloat = 46
        let gap: CGFloat = 20
        let rows = Int(ceil(Double(images.count) / Double(columns)))
        let width = CGFloat(columns) * cellWidth + CGFloat(columns - 1) * gap
        let height = CGFloat(rows) * (cellHeight + captionHeight) + CGFloat(rows - 1) * gap

        let sheet = NSImage(size: NSSize(width: width, height: height))
        sheet.lockFocus()
        NSColor(calibratedRed: 0.043, green: 0.047, blue: 0.063, alpha: 1).setFill()
        NSRect(origin: .zero, size: sheet.size).fill()
        let caption: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 20, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.7),
            .kern: 3
        ]
        for (index, (theme, image)) in images.enumerated() {
            let column = CGFloat(index % columns)
            let row = CGFloat(rows - 1 - index / columns)
            let x = column * (cellWidth + gap)
            let y = row * (cellHeight + captionHeight + gap)
            // Shots are 2x renders, so filling the cell at their point size
            // costs no sharpness; keep the aspect ratio and centre them.
            let drawSize = NSSize(width: image.size.width, height: image.size.height)
            let scale = min(cellWidth / drawSize.width, cellHeight / drawSize.height)
            let size = NSSize(width: drawSize.width * scale, height: drawSize.height * scale)
            let origin = NSPoint(x: x + (cellWidth - size.width) / 2, y: y + captionHeight + (cellHeight - size.height) / 2)
            image.draw(in: NSRect(origin: origin, size: size))
            let text = NSAttributedString(string: theme.title, attributes: caption)
            let textSize = text.size()
            text.draw(at: NSPoint(x: x + (cellWidth - textSize.width) / 2, y: y + (captionHeight - textSize.height) / 2))
        }
        sheet.unlockFocus()

        let tiff = try XCTUnwrap(sheet.tiffRepresentation)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try png.write(to: outputDir.appendingPathComponent("notch-themes.png"))
    }
}
