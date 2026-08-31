import AppKit
import SwiftUI

/// Owns the always-on panel pinned under the camera housing and the pointer
/// tracking that pulls its shelf down.
///
/// The panel is always sized to the expanded shelf so only SwiftUI animates;
/// while collapsed it ignores mouse events so the menu bar underneath keeps
/// working, and the pointer is watched through event monitors instead.
@MainActor
final class NotchController {
    /// Long enough for the peek to read as its own beat, short enough that the
    /// tray still feels like it opened on intent.
    private static let expandDelay: TimeInterval = 0.18
    private static let collapseDelay: TimeInterval = 0.25
    /// Backstop for the cases that produce no mouse-moved events, such as the
    /// pointer leaving via another Space or the display going to sleep.
    private static let pollInterval: TimeInterval = 0.4

    private let store: UsageStore
    private let settings: AppSettings
    private let notchState = NotchState()
    private let openHUD: () -> Void

    private var panel: NSPanel?
    private var monitors: [Any] = []
    private var pollTimer: Timer?
    private var expandWork: DispatchWorkItem?
    private var collapseWork: DispatchWorkItem?
    private var currentNotch: NotchGeometry.Notch?
    private var currentPanelFrame: CGRect = .zero
    private var currentShelfBounds: CGRect = .zero
    private var activeScreenNumber: Int?
    private var screenObserver: NSObjectProtocol?
    private var isEnabled = false

    init(store: UsageStore, settings: AppSettings, openHUD: @escaping () -> Void) {
        self.store = store
        self.settings = settings
        self.openHUD = openHUD
    }

    // MARK: - Lifecycle

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if enabled {
            createPanel()
            installMonitors()
            updateGeometry(force: true)
            panel?.orderFrontRegardless()
            AppLog.info("notch", "Notch mode enabled")
        } else {
            teardown()
            AppLog.info("notch", "Notch mode disabled")
        }
    }

    /// Call when the visible provider set changes: the shelf gets wider or
    /// narrower, so the panel has to follow.
    func refreshLayout() {
        guard isEnabled else { return }
        updateGeometry(force: true)
    }

    private func teardown() {
        cancelExpand()
        cancelCollapse()
        notchState.isExpanded = false
        notchState.isPeeking = false
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
        pollTimer?.invalidate()
        pollTimer = nil
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        panel?.orderOut(nil)
        panel = nil
        currentNotch = nil
        currentPanelFrame = .zero
        currentShelfBounds = .zero
        activeScreenNumber = nil
    }

    // MARK: - Panel

    private func createPanel() {
        let panel = NotchPanel(
            contentRect: NSRect(origin: .zero, size: CGSize(width: 240, height: 140)),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovable = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.animationBehavior = .none
        // Set last: `isFloatingPanel` and some style changes reset the level.
        // One step above the status bar so the shelf covers the menu bar it
        // grows over, while open menus (which sit far higher) still win.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.contentView = NSHostingView(
            rootView: NotchShelfView(
                store: store,
                settings: settings,
                notch: notchState,
                openHUD: { [weak self] in self?.openHUD() }
            )
        )
        self.panel = panel

        // Display arrangement changes move the notch, so re-measure.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isEnabled else { return }
                self.updateGeometry(force: true)
            }
        }
    }

    // MARK: - Geometry

    /// Retargets the panel at the display the pointer is on. Skipped while the
    /// shelf is open so it never teleports mid-interaction.
    private func updateGeometry(force: Bool = false) {
        guard isEnabled, let panel else { return }
        guard force || !notchState.isExpanded else { return }

        let point = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        guard let screen else { return }

        let screenNumber = screen.displayNumber
        let notch = screen.notchMetrics
        let providerCount = max(1, settings.visibleProviderCount)
        let frame = clamped(
            NotchGeometry.panelFrame(notch: notch, providerCount: providerCount),
            to: screen.frame
        )

        guard force || screenNumber != activeScreenNumber || frame != currentPanelFrame else { return }

        activeScreenNumber = screenNumber
        currentNotch = notch
        currentPanelFrame = frame
        currentShelfBounds = NotchGeometry.shelfBounds(notch: notch, providerCount: providerCount)
        panel.setFrame(frame, display: true)
        notchState.notchSize = notch.rect.size
        notchState.isHardwareNotch = notch.isHardware
    }

    private func clamped(_ frame: CGRect, to screenFrame: CGRect) -> CGRect {
        var result = frame
        result.size.width = min(result.width, screenFrame.width)
        result.origin.x = min(max(result.minX, screenFrame.minX), screenFrame.maxX - result.width)
        return result
    }

    // MARK: - Pointer tracking

    private func installMonitors() {
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.evaluatePointer()
            }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.evaluatePointer()
            }
            return event
        }) {
            monitors.append(local)
        }

        let timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.evaluatePointer()
            }
        }
        timer.tolerance = Self.pollInterval / 2
        pollTimer = timer
    }

    private func evaluatePointer() {
        guard isEnabled, panel != nil else { return }
        updateGeometry()
        guard let notch = currentNotch else { return }
        let point = NSEvent.mouseLocation


        if notchState.isExpanded {
            if NotchGeometry.stayZone(shelfBounds: currentShelfBounds).contains(point) {
                cancelCollapse()
            } else {
                scheduleCollapse()
            }
        } else {
            if NotchGeometry.hotZone(notch: notch).contains(point) {
                setPeeking(true)
                scheduleExpand()
            } else {
                setPeeking(false)
                cancelExpand()
            }
        }
    }

    /// The swell while the pointer waits out the expand delay. Paired with a
    /// haptic tick so trackpad users feel the notch notice them.
    private func setPeeking(_ peeking: Bool) {
        guard notchState.isPeeking != peeking else { return }
        if peeking {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            notchState.isPeeking = peeking
        } else {
            withAnimation(peeking ? HUDMotion.peekIn : HUDMotion.peekOut) {
                notchState.isPeeking = peeking
            }
        }
    }

    private func scheduleExpand() {
        guard expandWork == nil else { return }
        cancelCollapse()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.expandWork = nil
            guard let notch = self.currentNotch else { return }
            // Re-check: the pointer may have swept straight through by now.
            guard NotchGeometry.hotZone(notch: notch).contains(NSEvent.mouseLocation) else { return }
            self.setExpanded(true)
        }
        expandWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.expandDelay, execute: work)
    }

    private func cancelExpand() {
        expandWork?.cancel()
        expandWork = nil
    }

    private func scheduleCollapse() {
        guard collapseWork == nil else { return }
        cancelExpand()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.collapseWork = nil
            guard !NotchGeometry.stayZone(shelfBounds: self.currentShelfBounds).contains(NSEvent.mouseLocation) else { return }
            self.setExpanded(false)
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.collapseDelay, execute: work)
    }

    private func cancelCollapse() {
        collapseWork?.cancel()
        collapseWork = nil
    }

    private func setExpanded(_ expanded: Bool) {
        guard notchState.isExpanded != expanded else { return }
        // Only claim the pointer while the shelf is out; collapsed it must stay
        // out of the way of the menu bar.
        panel?.ignoresMouseEvents = !expanded
        if expanded { panel?.orderFrontRegardless() }

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            notchState.isExpanded = expanded
            notchState.isPeeking = false
        } else {
            withAnimation(expanded ? HUDMotion.open : HUDMotion.close) {
                notchState.isExpanded = expanded
                // The peek hands over to the open tray inside the same spring
                // so there is no half-beat snap between the two sizes.
                notchState.isPeeking = false
            }
        }
    }
}

/// AppKit keeps ordinary windows clear of the menu bar, which would drop the
/// shelf by the safe-area height and leave a seam under the camera housing.
private final class NotchPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private extension NSScreen {
    var displayNumber: Int? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.intValue
    }

    var notchMetrics: NotchGeometry.Notch {
        NotchGeometry.notch(
            screenFrame: frame,
            safeAreaTop: safeAreaInsets.top,
            auxiliaryLeftWidth: auxiliaryTopLeftArea?.width,
            auxiliaryRightWidth: auxiliaryTopRightArea?.width,
            menuBarHeight: frame.maxY - visibleFrame.maxY
        )
    }
}
