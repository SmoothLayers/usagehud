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
            return NSSize(width: 650, height: 96)
        }
        return NSSize(
            width: compact ? 350 : 430,
            height: compact && visibleProviderCount == 1 ? 96 : (compact ? 170 : 270)
        )
    }

    static func minimumSize(compact: Bool, visibleProviderCount: Int, layout: CompactLayout = .vertical) -> NSSize {
        if compact, layout == .horizontal, visibleProviderCount > 1 {
            return NSSize(width: 560, height: 88)
        }
        return NSSize(
            width: compact ? 280 : 360,
            height: compact && visibleProviderCount == 1 ? 88 : (compact ? 156 : 240)
        )
    }

    static func maximumSize(compact: Bool) -> NSSize {
        compact ? NSSize(width: 760, height: 420) : NSSize(width: 1_000, height: 760)
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
        let maximum = maximumSize(compact: compact)
        return NSSize(
            width: min(maximum.width, max(minimum.width, size.width)),
            height: min(maximum.height, max(minimum.height, size.height))
        )
    }

}

enum WindowInteraction {
    static func styleMask(locked: Bool) -> NSWindow.StyleMask {
        var mask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel, .fullSizeContentView]
        if !locked { mask.insert(.resizable) }
        return mask
    }

    static func level(alwaysOnTop: Bool) -> NSWindow.Level {
        alwaysOnTop ? .statusBar : .normal
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
    private var isApplyingProgrammaticResize = false
    private var panelOrderingRaised = false
    private var mouseMonitors: [Any] = []
    private let notificationService = UsageNotificationService()
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
    private let setupCompletedKey = "firstRunSetupCompleted"

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
        createStatusItem()
        applyInteractionSettings()
        // Clicking the non-activating panel raises it to the front of the
        // normal window level without ever activating this app, and windows
        // that join all Spaces keep that raised ordering across Space
        // switches. Sink the panel whenever the user changes app or Space so
        // it can never linger above other windows while Always on Top is off.
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
        // App and Space switches are not enough: clicking the panel raises
        // it, and no workspace notification fires while the user keeps
        // working inside the app that is already active. Track when the
        // panel gets raised by a click and sink it again on the next click
        // that lands anywhere else.
        if let localMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] event in
            MainActor.assumeIsolated {
                if let self, event.window === self.panel {
                    self.panelOrderingRaised = true
                }
            }
            return event
        }) {
            mouseMonitors.append(localMonitor)
        }
        if let globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.panelOrderingRaised else { return }
                self.sinkPanelIfNeeded(reason: "outside-click")
            }
        }) {
            mouseMonitors.append(globalMonitor)
        }
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
            case .sizing:
                self.resizePanel(compact: self.store.isCompact)
            case .timers:
                self.resizePanel(compact: self.store.isCompact)
            }
        }
        if UserDefaults.standard.bool(forKey: setupCompletedKey) {
            store.start()
            showPanel()
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
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        launchAtLoginItem = menu.addItem(withTitle: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
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
                showClaude: settings.showClaude
            )
            statusItem.button?.imagePosition = .imageLeading
        } else {
            statusItem.length = NSStatusItem.squareLength
            statusItem.button?.title = ""
            statusItem.button?.imagePosition = .imageOnly
        }
    }

    private func applyInteractionSettings() {
        guard panel != nil else { return }
        let wasAlwaysOnTop = panel.level != .normal
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
        } else if wasAlwaysOnTop, panel.isVisible {
            // Reset the ordering established by status-bar level. Merely changing
            // the level can leave the panel ahead of the active app until macOS
            // performs another window-ordering operation.
            sinkPanelIfNeeded(reason: "always-on-top-disabled")
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
        let designMaximum = WindowSizing.maximumSize(compact: compact)
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
        // permission alert) raises every window it owns, including the HUD
        // panel. Sink it again whenever Always on Top is off.
        sinkPanelIfNeeded(reason: "app-activated")
    }

    @objc private func workspaceOrderingChanged(_ notification: Notification) {
        sinkPanelIfNeeded(reason: "workspace-changed")
    }

    private func sinkPanelIfNeeded(reason: String) {
        guard panel != nil, panel.isVisible, !settings.alwaysOnTop else { return }
        panelOrderingRaised = false
        // orderBack(nil) is unreliable while this app is inactive: AppKit
        // constrains plain ordering calls to the app's own windows, so the
        // panel keeps floating above every other app. Ordering relative to
        // an explicit window number goes through the window server and works
        // across applications, so put the panel below the bottommost
        // on-screen normal-level window instead.
        if let bottommost = Self.bottommostNormalWindowNumber(excluding: panel.windowNumber) {
            panel.order(.below, relativeTo: bottommost)
            AppLog.info("window", "Panel sunk reason=\(reason) below=\(bottommost) alwaysOnTop=false")
        } else {
            panel.orderBack(nil)
            AppLog.info("window", "Panel sunk reason=\(reason) fallback=orderBack alwaysOnTop=false")
        }
    }

    private static func bottommostNormalWindowNumber(excluding panelWindowNumber: Int) -> Int? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let entries = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        // The list is ordered front to back, so the last normal-level entry
        // is the bottommost window on screen.
        return entries.last(where: { entry in
            (entry[kCGWindowLayer as String] as? Int) == 0
                && (entry[kCGWindowNumber as String] as? Int) != panelWindowNumber
        })?[kCGWindowNumber as String] as? Int
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
        showPanel()
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
        if settings.alwaysOnTop {
            panel.orderFrontRegardless()
        } else {
            // orderFront raises the panel just like a click does, so flag it
            // for sinking on the next click outside the panel.
            panel.orderFront(nil)
            panelOrderingRaised = true
        }
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
