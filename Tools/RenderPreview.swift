import AppKit
import SwiftUI

@main
struct RenderPreview {
    @MainActor
    static func main() throws {
        let now = Date()
        let store = UsageStore()
        store.isCompact = CommandLine.arguments.contains("--compact")
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

        let renderer = ImageRenderer(content: HUDView(store: store, hide: {}))
        renderer.scale = 2
        guard
            let image = renderer.nsImage,
            let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let png = bitmap.representation(using: .png, properties: [:])
        else {
            throw CocoaError(.fileWriteUnknown)
        }

        let outputPath = CommandLine.arguments.dropFirst().first(where: { !$0.hasPrefix("--") }) ?? "artifacts/usage-hud-preview.png"
        let output = URL(fileURLWithPath: outputPath)
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: output)
        print(output.path)
    }
}
