import AppKit
import ServiceManagement
import Sparkle
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

enum WindowSizing {
    private static let expandedWidthKey = "hudExpandedWindowWidth"
    private static let expandedHeightKey = "hudExpandedWindowHeight"
    private static let compactWidthKey = "hudCompactWindowWidth"
    private static let compactHeightKey = "hudCompactWindowHeight"

    static func defaultSize(compact: Bool, visibleProviderCount: Int, layout: CompactLayout = .vertical) -> NSSize {
        if compact, layout == .horizontal, visibleProviderCount > 1 {
            return NSSize(width: 325 * CGFloat(visibleProviderCount), height: 96)
        }
        return NSSize(
            width: compact ? 350 : (visibleProviderCount > 2 ? 630 : 430),
            height: compact ? 96 + 74 * CGFloat(max(0, visibleProviderCount - 1)) : 270
        )
    }

    static func minimumSize(compact: Bool, visibleProviderCount: Int, layout: CompactLayout = .vertical) -> NSSize {
        if compact, layout == .horizontal, visibleProviderCount > 1 {
            return NSSize(width: 280 * CGFloat(visibleProviderCount), height: 88)
        }
        return NSSize(
            width: compact ? 280 : (visibleProviderCount > 2 ? 540 : 360),
            height: compact ? 88 + 68 * CGFloat(max(0, visibleProviderCount - 1)) : 240
        )
    }

    static func maximumSize(compact: Bool, visibleProviderCount: Int = 2) -> NSSize {
        if compact, visibleProviderCount > 2 {
            return NSSize(width: 1_100, height: 600)
        }
        return compact ? NSSize(width: 760, height: 420) : NSSize(width: 1_000, height: 760)
    }

    static func savedSize(
        compact: Bool,
        visibleProviderCount: Int,
        layout: CompactLayout = .vertical,
        in defaults: UserDefaults = .standard
    ) -> NSSize? {
        let widthKey = compact ? compactWidthKey : expandedWidthKey
        let heightKey = compact ? compactHeightKey : expandedHeightKey
        guard defaults.object(forKey: widthKey) != nil, defaults.object(forKey: heightKey) != nil else {
            return nil
        }
        let size = NSSize(width: defaults.double(forKey: widthKey), height: defaults.double(forKey: heightKey))
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return nil }
        return clampedSize(
            size,
            compact: compact,
            visibleProviderCount: visibleProviderCount,
            layout: layout
        )
    }

    static func save(_ size: NSSize, compact: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(size.width, forKey: compact ? compactWidthKey : expandedWidthKey)
        defaults.set(size.height, forKey: compact ? compactHeightKey : expandedHeightKey)
    }

    static func reset(compact: Bool, in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: compact ? compactWidthKey : expandedWidthKey)
        defaults.removeObject(forKey: compact ? compactHeightKey : expandedHeightKey)
    }

    static func clampedSize(
        _ size: NSSize,
        compact: Bool,
        visibleProviderCount: Int,
        layout: CompactLayout = .vertical
    ) -> NSSize {
        let minimum = minimumSize(
            compact: compact,
            visibleProviderCount: visibleProviderCount,
            layout: layout
        )
        let maximum = maximumSize(compact: compact, visibleProviderCount: visibleProviderCount)
        return NSSize(
            width: min(maximum.width, max(minimum.width, size.width)),
            height: min(maximum.height, max(minimum.height, size.height))
        )
    }

}

enum WindowInteraction {
    // Keep the HUD with Finder's desktop content but below every normal
    // application window when Always on Top is disabled.
    static let desktopLevel = NSWindow.Level(
        rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1
    )

    static func styleMask(locked: Bool) -> NSWindow.StyleMask {
        var mask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel, .fullSizeContentView]
        if !locked { mask.insert(.resizable) }
        return mask
    }

    static func level(alwaysOnTop: Bool) -> NSWindow.Level {
        alwaysOnTop ? .statusBar : desktopLevel
    }

    static func collectionBehavior(alwaysOnTop: Bool) -> NSWindow.CollectionBehavior {
        var behavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .stationary]
        if alwaysOnTop { behavior.insert(.fullScreenAuxiliary) }
        return behavior
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let settings: AppSettings
    let store: UsageStore
    private var panel: NSPanel!
    private var settingsWindow: NSWindow?
    private var setupWindow: NSWindow?
    private var statusItem: NSStatusItem!
    private var launchAtLoginItem: NSMenuItem!
    private var compactModeItem: NSMenuItem!
    private var resetWindowSizeItem: NSMenuItem!
    private var usageAlertsItem: NSMenuItem!
    private var lockHUDItem: NSMenuItem!
    private var clickThroughItem: NSMenuItem!
    private var alwaysOnTopItem: NSMenuItem!
    private var notchModeItem: NSMenuItem!
    private var isApplyingProgrammaticResize = false
    private var panelUserHidden = false
    private let notificationService = UsageNotificationService()
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
    private let setupCompletedKey = "firstRunSetupCompleted"
    private let claudeStatusLineInstaller = ClaudeStatusLineInstaller()
    private var claudeLiveUsageServer: ClaudeLiveUsageServer?
    private var notchController: NotchController!

    override init() {
        let settings = AppSettings()
        self.settings = settings
        store = UsageStore(settings: settings)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLog.prepare()
        AppLog.info("app", "Usage HUD v\(AppMetadata.version) started")
        NSApp.setActivationPolicy(.accessory)
        createPanel()
        createNotchController()
        createStatusItem()
        applyInteractionSettings()
        reconcileLaunchAtLogin()
        // Reassert the desktop-layer placement after app and Space changes.
        // The level itself keeps the HUD below every normal app window.
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceCenter.addObserver(
            self,
            selector: #selector(workspaceOrderingChanged),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        workspaceCenter.addObserver(
            self,
            selector: #selector(workspaceOrderingChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        workspaceCenter.addObserver(
            self,
            selector: #selector(workspaceDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        updaterController.startUpdater()
        applyUpdateSettings()
        store.compactChanged = { [weak self] compact in
            self?.resizePanel(compact: compact)
            self?.compactModeItem.state = compact ? .on : .off
        }
        store.usageAlert = { [weak self] event in
            self?.notificationService.deliver(event)
        }
        store.usageDisplayChanged = { [weak self] in
            self?.updateStatusItemDisplay()
        }
        settings.changed = { [weak self] change in
            guard let self else { return }
            switch change {
            case .polling:
                self.store.applyPollingSettings()
            case .providers:
                self.store.applyProviderSettings()
                self.resizePanel(compact: self.store.isCompact)
                self.notchController.refreshLayout()
            case .appearance:
                self.panel.alphaValue = self.settings.hudOpacity
                self.resizePanel(compact: self.store.isCompact)
            case .menuBar:
                self.updateStatusItemDisplay()
            case .alerts:
                self.store.applyAlertSettings()
            case .interaction:
                self.applyInteractionSettings()
            case .updates:
                self.applyUpdateSettings()
            case .layout:
                self.resizePanel(compact: self.store.isCompact)
            case .notchTheme:
                // Each tray design needs a different amount of room.
                self.notchController.refreshLayout()
            case .sizing:
                self.resizePanel(compact: self.store.isCompact)
            case .timers:
                self.resizePanel(compact: self.store.isCompact)
            case .claudeLiveUsage:
                self.applyClaudeLiveUsageSetting()
            case .notch:
                self.applyNotchModeSetting()
            case .claudeWindowSchedule:
                self.store.applyClaudeWindowScheduleSettings()
            }
        }
        applyClaudeLiveUsageSetting()
        applyNotchModeSetting()
        if UserDefaults.standard.bool(forKey: setupCompletedKey) {
            store.start()
            if !settings.notchModeEnabled { showPanel() }
        } else {
            showSetupAssistant(firstRun: true)
        }
    }

    private func createPanel() {
        let compact = store.isCompact
        let size = desiredPanelSize(compact: compact)
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: WindowInteraction.styleMask(locked: settings.lockHUD),
            backing: .buffered,
            defer: false
        )
        panel.level = WindowInteraction.level(alwaysOnTop: settings.alwaysOnTop)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.alphaValue = settings.hudOpacity
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = WindowInteraction.collectionBehavior(alwaysOnTop: settings.alwaysOnTop)
        panel.animationBehavior = .utilityWindow
        configurePanelSizeLimits(compact: compact)
        panel.contentView = NSHostingView(
            rootView: HUDView(
                store: store,
                settings: settings,
                hide: { [weak self] in
                    AppLog.info("window", "HUD hidden from close button")
                    self?.panelUserHidden = true
                    self?.panel.orderOut(nil)
                }
            )
        )

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
        updateStatusItemDisplay()

        let menu = NSMenu()
        menu.addItem(withTitle: "Show Usage HUD", action: #selector(showHUD), keyEquivalent: "")
        menu.addItem(withTitle: "Refresh Now", action: #selector(refresh), keyEquivalent: "r")
        compactModeItem = menu.addItem(withTitle: "Compact Mode", action: #selector(toggleCompactMode), keyEquivalent: "")
        compactModeItem.state = store.isCompact ? .on : .off
        resetWindowSizeItem = menu.addItem(withTitle: "Reset Window Size", action: #selector(resetWindowSize), keyEquivalent: "")
        usageAlertsItem = menu.addItem(withTitle: "Usage Alerts", action: #selector(toggleUsageAlerts), keyEquivalent: "")
        usageAlertsItem.state = store.usageAlertsEnabled ? .on : .off
        lockHUDItem = menu.addItem(withTitle: "Lock HUD", action: #selector(toggleLockHUD), keyEquivalent: "")
        lockHUDItem.state = settings.lockHUD ? .on : .off
        clickThroughItem = menu.addItem(withTitle: "Click Through", action: #selector(toggleClickThrough), keyEquivalent: "")
        clickThroughItem.state = settings.clickThrough ? .on : .off
        alwaysOnTopItem = menu.addItem(withTitle: "Always on Top", action: #selector(toggleAlwaysOnTop), keyEquivalent: "")
        alwaysOnTopItem.state = settings.alwaysOnTop ? .on : .off
        notchModeItem = menu.addItem(withTitle: "Notch Mode", action: #selector(toggleNotchMode), keyEquivalent: "")
        notchModeItem.state = settings.notchModeEnabled ? .on : .off
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        launchAtLoginItem = menu.addItem(withTitle: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        updateLaunchAtLoginMenuItem()
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Usage HUD", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        statusItem.menu = menu
    }

    private func updateStatusItemDisplay() {
        guard statusItem != nil else { return }
        if settings.showMenuBarUsage {
            statusItem.length = NSStatusItem.variableLength
            statusItem.button?.title = " " + MenuBarUsageFormatter.text(
                codex: store.codex,
                claude: store.claude,
                showCodex: settings.showCodex,
                showClaude: settings.showClaude,
                kimi: store.kimi,
                showKimi: settings.showKimi,
                claudeStale: store.claudeIsStale,
                kimiStale: store.kimiIsStale
            )
            statusItem.button?.imagePosition = .imageLeading
        } else {
            statusItem.length = NSStatusItem.squareLength
            statusItem.button?.title = ""
            statusItem.button?.imagePosition = .imageOnly
        }
    }

    private func createNotchController() {
        notchController = NotchController(
            store: store,
            settings: settings,
            openHUD: { [weak self] in self?.showHUD() }
        )
    }

    private func applyNotchModeSetting() {
        notchController.setEnabled(settings.notchModeEnabled)
        notchModeItem.state = settings.notchModeEnabled ? .on : .off
        // The notch tray replaces the floating HUD rather than doubling it up.
        // "Show Usage HUD" still brings the window back on demand.
        guard panel != nil else { return }
        if settings.notchModeEnabled {
            panel.orderOut(nil)
        } else if !panelUserHidden {
            panel.orderFrontRegardless()
        }
    }

    private func applyInteractionSettings() {
        guard panel != nil else { return }
        let wasAlwaysOnTop = panel.level == WindowInteraction.level(alwaysOnTop: true)
        panel.isMovableByWindowBackground = !settings.lockHUD
        panel.ignoresMouseEvents = settings.clickThrough
        panel.level = WindowInteraction.level(alwaysOnTop: settings.alwaysOnTop)
        panel.collectionBehavior = WindowInteraction.collectionBehavior(alwaysOnTop: settings.alwaysOnTop)
        // Reassigning an identical styleMask still churns the server-side
        // window and can reorder it, so only touch it on a real change.
        let styleMask = WindowInteraction.styleMask(locked: settings.lockHUD)
        if panel.styleMask != styleMask {
            panel.styleMask = styleMask
        }
        lockHUDItem?.state = settings.lockHUD ? .on : .off
        clickThroughItem?.state = settings.clickThrough ? .on : .off
        alwaysOnTopItem?.state = settings.alwaysOnTop ? .on : .off
        if settings.alwaysOnTop, panel.isVisible {
            panel.orderFrontRegardless()
        } else if wasAlwaysOnTop {
            // Reinsert the panel at the front of the desktop layer after
            // dropping it from status-bar level.
            updatePanelOrdering(reason: "always-on-top-disabled")
        }
        AppLog.info("window", "Interaction changed locked=\(settings.lockHUD) clickThrough=\(settings.clickThrough) alwaysOnTop=\(settings.alwaysOnTop)")
    }

    private func applyUpdateSettings() {
        updaterController.updater.automaticallyChecksForUpdates = settings.automaticUpdateChecks
        updaterController.updater.automaticallyDownloadsUpdates = settings.automaticUpdateChecks
        AppLog.info("updates", "Sparkle automatic updates enabled=\(settings.automaticUpdateChecks)")
    }

    private func resizePanel(compact: Bool) {
        let newSize = desiredPanelSize(compact: compact)
        configurePanelSizeLimits(compact: compact)
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
        isApplyingProgrammaticResize = true
        panel.setFrame(frame, display: true, animate: false)
        isApplyingProgrammaticResize = false
        AppLog.info("window", "Mode changed compact=\(compact) x=\(Int(frame.origin.x.rounded())) y=\(Int(frame.origin.y.rounded()))")
    }

    private func desiredPanelSize(compact: Bool) -> NSSize {
        let base = WindowSizing.savedSize(
            compact: compact,
            visibleProviderCount: settings.visibleProviderCount,
            layout: settings.compactLayout
        ) ?? WindowSizing.defaultSize(
            compact: compact,
            visibleProviderCount: settings.visibleProviderCount,
            layout: settings.compactLayout
        )
        let minimum = effectiveMinimumSize(compact: compact)
        return NSSize(width: max(base.width, minimum.width), height: max(base.height, minimum.height))
    }

    private func configurePanelSizeLimits(compact: Bool) {
        panel?.minSize = effectiveMinimumSize(compact: compact)
        let designMaximum = WindowSizing.maximumSize(
            compact: compact,
            visibleProviderCount: settings.visibleProviderCount
        )
        if let visible = panel?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame {
            panel?.maxSize = NSSize(
                width: max(panel.minSize.width, min(designMaximum.width, visible.width)),
                height: max(panel.minSize.height, min(designMaximum.height, visible.height))
            )
        } else {
            panel?.maxSize = designMaximum
        }
    }

    private func effectiveMinimumSize(compact: Bool) -> NSSize {
        var minimum = WindowSizing.minimumSize(
            compact: compact,
            visibleProviderCount: settings.visibleProviderCount,
            layout: settings.compactLayout
        )
        let scaleIncrease = max(0, settings.textScale - 1)
        if scaleIncrease > 0 {
            minimum.width += compact ? scaleIncrease * 120 : scaleIncrease * 400
            minimum.height += compact ? scaleIncrease * 70 : scaleIncrease * 120
        }
        if compact {
            minimum.height += 29
        }
        return minimum
    }

    func windowDidMove(_ notification: Notification) {
        guard
            !isApplyingProgrammaticResize,
            let movedWindow = notification.object as? NSWindow,
            movedWindow === panel
        else { return }
        savePanelOrigin(movedWindow.frame.origin)
    }

    func windowDidResize(_ notification: Notification) {
        guard
            !isApplyingProgrammaticResize,
            let resizedWindow = notification.object as? NSWindow,
            resizedWindow === panel
        else { return }
        WindowSizing.save(resizedWindow.frame.size, compact: store.isCompact)
        AppLog.info(
            "window",
            "Size saved compact=\(store.isCompact) width=\(Int(resizedWindow.frame.width.rounded())) height=\(Int(resizedWindow.frame.height.rounded()))"
        )
    }

    func windowDidChangeScreen(_ notification: Notification) {
        configurePanelSizeLimits(compact: store.isCompact)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Activating the app (opening Settings, the setup assistant, or a
        // permission alert) can disturb the HUD panel's ordering. Re-anchor it
        // to the desktop whenever Always on Top is off.
        updatePanelOrdering(reason: "app-activated")
        store.refreshStaleProviders(trigger: "app-activated")
        store.handleClaudeWindowScheduleEvent(trigger: "app-activated")
    }

    @objc private func workspaceDidWake(_ notification: Notification) {
        AppLog.info("scheduler", "System wake detected; checking provider freshness")
        store.refreshStaleProviders(trigger: "system-wake")
        store.handleClaudeWindowScheduleEvent(trigger: "system-wake")
    }

    private func applyClaudeLiveUsageSetting() {
        if settings.claudeLiveUsageEnabled {
            do {
                let result = try claudeStatusLineInstaller.install()
                store.setClaudeLiveStatus(result.detail)
                switch result {
                case .installed, .alreadyInstalled, .chainedCCStatusLine:
                    if claudeLiveUsageServer == nil {
                        let server = ClaudeLiveUsageServer(endpointURL: claudeStatusLineInstaller.endpointURL)
                        try server.start { [weak self] snapshot in
                            self?.store.ingestClaudeLive(snapshot)
                        }
                        claudeLiveUsageServer = server
                    }
                case .userStatusLinePresent, .userOptedOut:
                    claudeLiveUsageServer?.stop()
                    claudeLiveUsageServer = nil
                }
                AppLog.info("claude-live", result.detail)
            } catch {
                claudeLiveUsageServer?.stop()
                claudeLiveUsageServer = nil
                let detail = "Live Claude updates unavailable: \(error.localizedDescription)"
                store.setClaudeLiveStatus(detail)
                AppLog.error("claude-live", detail)
            }
        } else {
            claudeLiveUsageServer?.stop()
            claudeLiveUsageServer = nil
            do {
                try claudeStatusLineInstaller.uninstall()
                store.setClaudeLiveStatus(nil)
            } catch {
                let detail = "Could not remove managed Claude status line: \(error.localizedDescription)"
                store.setClaudeLiveStatus(detail)
                AppLog.error("claude-live", detail)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stopClaudeWindowSchedule()
        claudeLiveUsageServer?.stop()
        notchController.setEnabled(false)
    }

    @objc private func workspaceOrderingChanged(_ notification: Notification) {
        updatePanelOrdering(reason: "workspace-changed")
    }

    private func updatePanelOrdering(reason: String) {
        guard panel != nil, panel.isVisible, !panelUserHidden, !settings.alwaysOnTop else { return }
        panel.orderFrontRegardless()
        AppLog.info(
            "window",
            "Panel anchored reason=\(reason) desktopLevel=\(panel.level.rawValue) alwaysOnTop=false"
        )
    }

    @objc private func showHUD() {
        repairPanelFrame()
        showPanel()
        AppLog.info("window", "HUD shown from menu")
    }

    @objc private func refresh() {
        store.refresh()
        repairPanelFrame()
    }

    @objc private func toggleCompactMode() {
        store.toggleCompact()
    }

    @objc private func resetWindowSize() {
        let compact = store.isCompact
        WindowSizing.reset(compact: compact)
        resizePanel(compact: compact)
        AppLog.info("window", "Size reset to default compact=\(compact)")
    }

    @objc private func toggleUsageAlerts() {
        requestUsageAlerts(!store.usageAlertsEnabled)
    }

    @objc private func toggleLockHUD() {
        settings.setLockHUD(!settings.lockHUD)
    }

    @objc private func toggleClickThrough() {
        settings.setClickThrough(!settings.clickThrough)
    }

    @objc private func toggleAlwaysOnTop() {
        settings.setAlwaysOnTop(!settings.alwaysOnTop)
    }

    @objc private func toggleNotchMode() {
        settings.setNotchModeEnabled(!settings.notchModeEnabled)
    }

    @objc private func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    private func requestUsageAlerts(_ enabled: Bool) {
        if !enabled {
            store.setUsageAlertsEnabled(false)
            usageAlertsItem.state = .off
            return
        }

        Task {
            let allowed = await notificationService.requestPermission()
            if allowed {
                store.setUsageAlertsEnabled(true)
                usageAlertsItem.state = .on
            } else {
                usageAlertsItem.state = .off
                let alert = NSAlert()
                alert.messageText = "Usage alerts are turned off"
                alert.informativeText = "Allow notifications for Usage HUD in System Settings to receive low-usage and reset alerts."
                alert.addButton(withTitle: "Open Notification Settings")
                alert.addButton(withTitle: "Cancel")
                if alert.runModal() == .alertFirstButtonReturn,
                   let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    @objc private func showSettings() {
        if settingsWindow == nil {
            let view = SettingsView(
                settings: settings,
                store: store,
                setUsageAlerts: { [weak self] enabled in
                    self?.requestUsageAlerts(enabled)
                },
                checkForUpdates: { [weak self] in
                    self?.checkForUpdates()
                },
                runSetupAssistant: { [weak self] in
                    self?.runSetupAssistant()
                },
                openLogs: { [weak self] in
                    self?.openLogs()
                },
                resetWindowSize: { [weak self] in
                    self?.resetWindowSize()
                }
            )
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 720),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Usage HUD Settings"
            window.titlebarAppearsTransparent = true
            window.backgroundColor = NSColor(red: 0.055, green: 0.065, blue: 0.075, alpha: 1)
            window.contentView = NSHostingView(rootView: view)
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        AppLog.info("app", "Settings opened")
    }

    @objc private func runSetupAssistant() {
        showSetupAssistant(firstRun: false)
    }

    private func showSetupAssistant(firstRun: Bool) {
        if setupWindow == nil {
            let view = FirstRunSetupView(
                settings: settings,
                store: store,
                requestNotifications: { [weak self] in
                    guard let self else { return false }
                    let allowed = await self.notificationService.requestPermission()
                    if allowed {
                        self.store.setUsageAlertsEnabled(true)
                        self.usageAlertsItem.state = .on
                    }
                    return allowed
                },
                finish: { [weak self] in self?.finishSetup(firstRun: firstRun) }
            )
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 620, height: 500),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Set Up Usage HUD"
            window.titlebarAppearsTransparent = true
            window.backgroundColor = NSColor(red: 0.045, green: 0.055, blue: 0.068, alpha: 1)
            window.contentView = NSHostingView(rootView: view)
            window.isReleasedWhenClosed = false
            window.center()
            setupWindow = window
        }
        setupWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        AppLog.info("setup", "Setup assistant opened firstRun=\(firstRun)")
    }

    private func finishSetup(firstRun: Bool) {
        UserDefaults.standard.set(true, forKey: setupCompletedKey)
        setupWindow?.orderOut(nil)
        setupWindow = nil
        if firstRun { store.start() }
        repairPanelFrame()
        if !settings.notchModeEnabled { showPanel() }
        AppLog.info("setup", "Setup assistant completed firstRun=\(firstRun)")
    }

    private func repairPanelFrame() {
        let expectedSize = desiredPanelSize(compact: store.isCompact)
        configurePanelSizeLimits(compact: store.isCompact)
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
        isApplyingProgrammaticResize = true
        panel.setFrame(frame, display: true)
        isApplyingProgrammaticResize = false
    }

    private func showPanel() {
        panelUserHidden = false
        panel.orderFrontRegardless()
    }

    private func savePanelOrigin(_ origin: NSPoint) {
        UserDefaults.standard.set(origin.x, forKey: WindowPlacement.originXKey)
        UserDefaults.standard.set(origin.y, forKey: WindowPlacement.originYKey)
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
        let enable = !settings.launchAtLogin
        do {
            if enable {
                try SMAppService.mainApp.register()
                settings.setLaunchAtLogin(true)
                AppLog.info("app", "Launch at Login enabled status=\(SMAppService.mainApp.status.rawValue)")
                if SMAppService.mainApp.status == .requiresApproval {
                    promptForLoginItemApproval()
                }
            } else {
                settings.setLaunchAtLogin(false)
                if SMAppService.mainApp.status != .notRegistered {
                    try SMAppService.mainApp.unregister()
                }
                AppLog.info("app", "Launch at Login disabled")
            }
        } catch {
            AppLog.warning("app", "Launch at Login toggle failed: \(error.localizedDescription)")
            let alert = NSAlert(error: error)
            alert.messageText = "Couldn’t change Launch at Login"
            alert.runModal()
        }
        updateLaunchAtLoginMenuItem()
    }

    /// A login-item registration points at the app where it was registered;
    /// rebuilding, updating, or moving the bundle strands it and macOS just
    /// stops launching it — silently. So the stored intent, not the system,
    /// is the source of truth, and every launch re-registers the copy that
    /// actually ran.
    private func reconcileLaunchAtLogin() {
        let status = SMAppService.mainApp.status
        // Registrations made before the intent was persisted still count as
        // the user asking for it.
        if status == .enabled, !settings.launchAtLogin {
            settings.setLaunchAtLogin(true)
        }
        guard settings.launchAtLogin else { return }
        do {
            try SMAppService.mainApp.register()
            AppLog.info("app", "Launch at Login re-registered previousStatus=\(status.rawValue) status=\(SMAppService.mainApp.status.rawValue)")
        } catch {
            AppLog.warning("app", "Launch at Login re-registration failed: \(error.localizedDescription)")
        }
        updateLaunchAtLoginMenuItem()
    }

    /// macOS answered `register` with "pending user approval": the item sits
    /// disabled in System Settings until the user flips it there.
    private func promptForLoginItemApproval() {
        let alert = NSAlert()
        alert.messageText = "Launch at Login needs your approval"
        alert.informativeText = "macOS added Usage HUD to Login Items but left it off. Enable it under System Settings → General → Login Items."
        alert.addButton(withTitle: "Open Login Items")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    /// The checkmark reflects reality, not hope: intent that macOS has not
    /// honored yet (pending approval, failed registration) shows as off.
    private func updateLaunchAtLoginMenuItem() {
        launchAtLoginItem.state = settings.launchAtLogin && SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func quit() {
        AppLog.info("app", "Usage HUD quitting")
        AppLog.flush()
        NSApp.terminate(nil)
    }
}
