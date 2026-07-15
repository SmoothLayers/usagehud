import AppKit
import SwiftUI

@main
struct RenderPreview {
    @MainActor
    static func main() throws {
        let now = Date()
        let suiteName = "UsageHUD.RenderPreview"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AppSettings(defaults: defaults)
        let store = UsageStore(defaults: defaults, settings: settings)
        store.isCompact = CommandLine.arguments.contains("--compact")
        if CommandLine.arguments.contains("--horizontal") {
            settings.setCompactLayout(.horizontal)
        }
        if CommandLine.arguments.contains("--custom-theme") {
            settings.setTextScale(1.15)
            settings.setBarThickness(6)
            settings.setCornerRadius(18)
            settings.setAccent("63C5FF", provider: .codex)
            settings.setAccent("FF6B81", provider: .claude)
        }
        store.codex = .loaded(ProviderUsage(
            kind: .codex,
            plan: "Plus",
            primary: UsageWindow(label: "5h window", usedPercent: 28, resetsAt: now.addingTimeInterval(7_800)),
            secondary: UsageWindow(label: "7d window", usedPercent: 42, resetsAt: now.addingTimeInterval(320_000)),
            fetchedAt: now
        ))
        store.claude = .loaded(ProviderUsage(
            kind: .claude,
            plan: "Pro",
            primary: UsageWindow(label: "5h window", usedPercent: 61, resetsAt: now.addingTimeInterval(3_900)),
            secondary: UsageWindow(label: "7d window", usedPercent: 35, resetsAt: now.addingTimeInterval(410_000)),
            fetchedAt: now
        ))
        if CommandLine.arguments.contains("--stale") {
            store.claudeNotice = "Rate limited · retry in 5m"
        }
        store.codexLastSuccess = now.addingTimeInterval(-45)
        store.claudeLastSuccess = now.addingTimeInterval(-90)
        store.codexNextRefresh = now.addingTimeInterval(75)
        store.claudeNextRefresh = now.addingTimeInterval(30)

        let content: AnyView
        if CommandLine.arguments.contains("--settings") {
            content = AnyView(SettingsView(
                settings: settings,
                store: store,
                updateChecker: UpdateChecker(),
                setUsageAlerts: { _ in },
                checkForUpdates: {},
                resetWindowSize: {}
            ))
        } else {
            let wide = CommandLine.arguments.contains("--wide")
            let custom = CommandLine.arguments.contains("--custom-theme")
            let horizontal = store.isCompact && settings.compactLayout == .horizontal
            let size = store.isCompact
                ? NSSize(
                    width: horizontal ? 650 : (wide ? 620 : (custom ? 380 : 350)),
                    height: horizontal ? 119 : (wide ? 264 : (custom ? 199 : 185))
                )
                : NSSize(width: wide ? 760 : (custom ? 500 : 430), height: wide ? 420 : (custom ? 310 : 270))
            content = AnyView(
                HUDView(store: store, settings: settings, hide: {})
                    .environment(\.colorScheme, .dark)
                    .frame(width: size.width, height: size.height)
            )
        }
        let outputPath = CommandLine.arguments.dropFirst().first(where: { !$0.hasPrefix("--") }) ?? "artifacts/usage-hud-preview.png"
        let output = URL(fileURLWithPath: outputPath)
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        let png: Data
        if CommandLine.arguments.contains("--settings") {
            let size = NSSize(width: 520, height: 720)
            let hostingView = NSHostingView(rootView: content)
            hostingView.frame = NSRect(origin: .zero, size: size)
            let window = NSWindow(
                contentRect: hostingView.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.contentView = hostingView
            hostingView.layoutSubtreeIfNeeded()
            guard let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: 1_040,
                pixelsHigh: 1_440,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ) else { throw CocoaError(.fileWriteUnknown) }
            bitmap.size = size
            hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
            guard let data = bitmap.representation(using: .png, properties: [:]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            png = data
        } else {
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            guard
                let image = renderer.nsImage,
                let tiff = image.tiffRepresentation,
                let bitmap = NSBitmapImageRep(data: tiff),
                let data = bitmap.representation(using: .png, properties: [:])
            else {
                throw CocoaError(.fileWriteUnknown)
            }
            png = data
        }
        try png.write(to: output)
        print(output.path)
    }
}
