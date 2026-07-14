import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = UsageStore()
    private var panel: NSPanel!
    private var statusItem: NSStatusItem!
    private var launchAtLoginItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        createPanel()
        createStatusItem()
        store.compactChanged = { [weak self] compact in
            self?.resizePanel(compact: compact)
        }
        store.start()
        panel.orderFrontRegardless()
    }

    private func createPanel() {
        let compact = store.isCompact
        let size = NSSize(width: compact ? 340 : 430, height: compact ? 170 : 250)
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
            self?.panel.orderOut(nil)
        })

        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            let origin = NSPoint(
                x: visible.maxX - size.width - 18,
                y: visible.maxY - size.height - 18
            )
            panel.setFrameOrigin(origin)
        }
    }

    private func createStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "gauge.with.dots.needle.67percent", accessibilityDescription: "Usage HUD")

        let menu = NSMenu()
        menu.addItem(withTitle: "Show Usage HUD", action: #selector(showHUD), keyEquivalent: "")
        menu.addItem(withTitle: "Refresh Now", action: #selector(refresh), keyEquivalent: "r")
        menu.addItem(.separator())
        launchAtLoginItem = menu.addItem(withTitle: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Usage HUD", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        statusItem.menu = menu
    }

    private func resizePanel(compact: Bool) {
        let newSize = NSSize(width: compact ? 340 : 430, height: compact ? 170 : 250)
        var frame = panel.frame
        frame.origin.y += frame.height - newSize.height
        frame.size = newSize
        panel.setFrame(frame, display: true, animate: true)
    }

    @objc private func showHUD() {
        panel.orderFrontRegardless()
    }

    @objc private func refresh() {
        store.refresh()
        panel.orderFrontRegardless()
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
        NSApp.terminate(nil)
    }
}
