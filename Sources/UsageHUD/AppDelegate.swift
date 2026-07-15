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
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let settings: AppSettings
    let store: UsageStore
    private var panel: NSPanel!
    private var settingsWindow: NSWindow?
    private var statusItem: NSStatusItem!
    private var launchAtLoginItem: NSMenuItem!
    private var compactModeItem: NSMenuItem!
    private var resetWindowSizeItem: NSMenuItem!
    private var usageAlertsItem: NSMenuItem!
    private var lockHUDItem: NSMenuItem!
    private var clickThroughItem: NSMenuItem!
    private var updateItem: NSMenuItem!
    private var updateTimer: Timer?
    private var isApplyingProgrammaticResize = false
    private let lastUpdateCheckKey = "lastAutomaticUpdateCheck"
    private let notificationService = UsageNotificationService()
    private let updateChecker = UpdateChecker()

    override init() {
        let settings = AppSettings()
        self.settings = settings
        store = UsageStore(settings: settings)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLog.clearForFreshStartIfNeeded()
        AppLog.prepare()
        AppLog.info("app", "Usage HUD v\(AppMetadata.version) started")
        NSApp.setActivationPolicy(.accessory)
        createPanel()
        createStatusItem()
        applyInteractionSettings()
        updateChecker.statusChanged = { [weak self] status in
            self?.updateUpdateMenu(for: status)
        }
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
                self.configureUpdateChecks()
            case .layout:
                self.resizePanel(compact: self.store.isCompact)
            case .sizing:
                self.resizePanel(compact: self.store.isCompact)
            case .timers:
                self.resizePanel(compact: self.store.isCompact)
            }
        }
        store.start()
        configureUpdateChecks()
        panel.orderFrontRegardless()
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
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.alphaValue = settings.hudOpacity
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
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
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        updateItem = menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        menu.addItem(withTitle: "Open Logs…", action: #selector(openLogs), keyEquivalent: "l")
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
        panel.isMovableByWindowBackground = !settings.lockHUD
        panel.ignoresMouseEvents = settings.clickThrough
        panel.styleMask = WindowInteraction.styleMask(locked: settings.lockHUD)
        lockHUDItem?.state = settings.lockHUD ? .on : .off
        clickThroughItem?.state = settings.clickThrough ? .on : .off
        AppLog.info("window", "Interaction changed locked=\(settings.lockHUD) clickThrough=\(settings.clickThrough)")
    }

    private func configureUpdateChecks() {
        updateTimer?.invalidate()
        updateTimer = nil
        guard settings.automaticUpdateChecks else { return }
        let lastCheck = UserDefaults.standard.object(forKey: lastUpdateCheckKey) as? Date
        if UpdateCheckSchedule.shouldRun(lastCheck: lastCheck) {
            runUpdateCheck()
        }
        let timer = Timer(timeInterval: UpdateCheckSchedule.interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.runUpdateCheck() }
        }
        updateTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func updateUpdateMenu(for status: UpdateStatus) {
        guard updateItem != nil else { return }
        switch status {
        case .checking:
            updateItem.title = "Checking for Updates…"
            updateItem.isEnabled = false
        case let .available(release):
            updateItem.title = "Update Available — v\(release.version)…"
            updateItem.isEnabled = true
        default:
            updateItem.title = "Check for Updates…"
            updateItem.isEnabled = true
        }
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

    @objc private func resetWindowSize() {
        let compact = store.isCompact
        WindowSizing.reset(compact: compact)
        resizePanel(compact: compact)
        panel.orderFrontRegardless()
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

    @objc private func checkForUpdates() {
        if case let .available(release) = updateChecker.status {
            NSWorkspace.shared.open(release.url)
            return
        }
        runUpdateCheck()
    }

    private func runUpdateCheck() {
        Task {
            await updateChecker.check()
            UserDefaults.standard.set(Date.now, forKey: lastUpdateCheckKey)
        }
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
                updateChecker: updateChecker,
                setUsageAlerts: { [weak self] enabled in
                    self?.requestUsageAlerts(enabled)
                },
                checkForUpdates: { [weak self] in
                    self?.checkForUpdates()
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
