import AppKit
import ServiceManagement
import SwiftUI

enum WindowPlacement {
    static let originXKey = "hudWindowOriginX"
    static let originYKey = "hudWindowOriginY"

    static func savedOrigin(in defaults: UserDefaults = .standard) -> NSPoint? {
        guard
            defaults.object(forKey: originXKey) != nil,
            defaults.object(forKey: originYKey) != nil
        else { return nil }
        return NSPoint(
            x: defaults.double(forKey: originXKey),
            y: defaults.double(forKey: originYKey)
        )
    }

    static func clampedOrigin(_ origin: NSPoint, windowSize: NSSize, visibleFrame: NSRect) -> NSPoint {
        let maximumX = max(visibleFrame.minX, visibleFrame.maxX - windowSize.width)
        let maximumY = max(visibleFrame.minY, visibleFrame.maxY - windowSize.height)
        return NSPoint(
            x: min(max(origin.x, visibleFrame.minX), maximumX),
            y: min(max(origin.y, visibleFrame.minY), maximumY)
        )
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let store = UsageStore()
    private var panel: NSPanel!
    private var statusItem: NSStatusItem!
    private var launchAtLoginItem: NSMenuItem!
    private var compactModeItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLog.clearForFreshStartIfNeeded()
        AppLog.prepare()
        AppLog.info("app", "Usage HUD v\(AppMetadata.version) started")
        NSApp.setActivationPolicy(.accessory)
        createPanel()
        createStatusItem()
        store.compactChanged = { [weak self] compact in
            self?.resizePanel(compact: compact)
            self?.compactModeItem.state = compact ? .on : .off
        }
        store.start()
        panel.orderFrontRegardless()
    }

    private func createPanel() {
        let compact = store.isCompact
        let size = NSSize(width: compact ? 350 : 430, height: compact ? 170 : 250)
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.animationBehavior = .utilityWindow
        panel.contentView = NSHostingView(rootView: HUDView(store: store) { [weak self] in
            AppLog.info("window", "HUD hidden from close button")
            self?.panel.orderOut(nil)
        })

        if let savedOrigin = WindowPlacement.savedOrigin(), let screen = screen(for: savedOrigin, windowSize: size) {
            let origin = WindowPlacement.clampedOrigin(
                savedOrigin,
                windowSize: size,
                visibleFrame: screen.visibleFrame
            )
            panel.setFrameOrigin(origin)
            AppLog.info("window", "Position restored x=\(Int(origin.x.rounded())) y=\(Int(origin.y.rounded()))")
        } else if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            let origin = NSPoint(
                x: visible.maxX - size.width - 18,
                y: visible.maxY - size.height - 18
            )
            panel.setFrameOrigin(origin)
        }
        panel.delegate = self
    }

    private func screen(for origin: NSPoint, windowSize: NSSize) -> NSScreen? {
        let center = NSPoint(x: origin.x + windowSize.width / 2, y: origin.y + windowSize.height / 2)
        return NSScreen.screens.first(where: { $0.visibleFrame.contains(center) }) ?? NSScreen.main
    }

    private func createStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "gauge.with.dots.needle.67percent", accessibilityDescription: "Usage HUD")

        let menu = NSMenu()
        menu.addItem(withTitle: "Show Usage HUD", action: #selector(showHUD), keyEquivalent: "")
        menu.addItem(withTitle: "Refresh Now", action: #selector(refresh), keyEquivalent: "r")
        compactModeItem = menu.addItem(withTitle: "Compact Mode", action: #selector(toggleCompactMode), keyEquivalent: "")
        compactModeItem.state = store.isCompact ? .on : .off
        menu.addItem(.separator())
        menu.addItem(withTitle: "Open Logs…", action: #selector(openLogs), keyEquivalent: "l")
        menu.addItem(.separator())
        launchAtLoginItem = menu.addItem(withTitle: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Usage HUD", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        statusItem.menu = menu
    }

    private func resizePanel(compact: Bool) {
        let newSize = NSSize(width: compact ? 350 : 430, height: compact ? 170 : 250)
        var frame = panel.frame
        frame.origin.y += frame.height - newSize.height
        frame.size = newSize
        if let targetScreen = panel.screen ?? screen(for: frame.origin, windowSize: newSize) {
            frame.origin = WindowPlacement.clampedOrigin(
                frame.origin,
                windowSize: newSize,
                visibleFrame: targetScreen.visibleFrame
            )
        }
        panel.setFrame(frame, display: true, animate: true)
        AppLog.info("window", "Mode changed compact=\(compact) x=\(Int(frame.origin.x.rounded())) y=\(Int(frame.origin.y.rounded()))")
    }

    func windowDidMove(_ notification: Notification) {
        guard let movedWindow = notification.object as? NSWindow, movedWindow === panel else { return }
        UserDefaults.standard.set(movedWindow.frame.origin.x, forKey: WindowPlacement.originXKey)
        UserDefaults.standard.set(movedWindow.frame.origin.y, forKey: WindowPlacement.originYKey)
    }

    @objc private func showHUD() {
        repairPanelFrame()
        panel.orderFrontRegardless()
        AppLog.info("window", "HUD shown from menu")
    }

    @objc private func refresh() {
        store.refresh()
        repairPanelFrame()
        panel.orderFrontRegardless()
    }

    @objc private func toggleCompactMode() {
        store.toggleCompact()
        panel.orderFrontRegardless()
    }

    private func repairPanelFrame() {
        let expectedSize = NSSize(width: store.isCompact ? 350 : 430, height: store.isCompact ? 170 : 250)
        var frame = panel.frame
        let topEdge = frame.maxY
        frame.size = expectedSize
        frame.origin.y = topEdge - expectedSize.height

        if let targetScreen = panel.screen ?? screen(for: frame.origin, windowSize: expectedSize) {
            frame.origin = WindowPlacement.clampedOrigin(
                frame.origin,
                windowSize: expectedSize,
                visibleFrame: targetScreen.visibleFrame
            )
        }
        panel.setFrame(frame, display: true)
    }

    @objc private func openLogs() {
        AppLog.info("app", "Log file opened from menu")
        AppLog.flush()
        guard AppLog.prepare() else {
            let alert = NSAlert()
            alert.messageText = "Couldn’t create the log file"
            alert.informativeText = AppLog.fileURL.path
            alert.runModal()
            return
        }
        NSWorkspace.shared.open(AppLog.fileURL)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
                launchAtLoginItem.state = .off
            } else {
                try SMAppService.mainApp.register()
                launchAtLoginItem.state = .on
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Couldn’t change Launch at Login"
            alert.runModal()
        }
    }

    @objc private func quit() {
        AppLog.info("app", "Usage HUD quitting")
        AppLog.flush()
        NSApp.terminate(nil)
    }
}
