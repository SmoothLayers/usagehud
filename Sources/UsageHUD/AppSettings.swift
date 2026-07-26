import Foundation

enum AppSettingsChange {
    case polling
    case providers
    case appearance
    case menuBar
    case alerts
    case interaction
    case updates
    case layout
    case sizing
    case timers
    case claudeLiveUsage
}

final class AppSettings: ObservableObject {
    static let codexPollingChoices: [TimeInterval] = [2 * 60, 5 * 60, 10 * 60, 15 * 60]
    static let claudePollingChoices: [TimeInterval] = [5 * 60, 10 * 60, 15 * 60]
    static let defaultCodexPollingInterval: TimeInterval = 2 * 60
    static let defaultClaudePollingInterval: TimeInterval = 5 * 60

    @Published private(set) var codexPollingInterval: TimeInterval
    @Published private(set) var claudePollingInterval: TimeInterval
    @Published private(set) var showCodex: Bool
    @Published private(set) var showClaude: Bool
    @Published private(set) var hudOpacity: Double
    @Published private(set) var showMenuBarUsage: Bool
    @Published private(set) var showResetCountdown: Bool
    @Published private(set) var showRefreshCountdown: Bool
    @Published private(set) var alertThresholds: [String: Int]
    @Published private(set) var lockHUD: Bool
    @Published private(set) var clickThrough: Bool
    @Published private(set) var alwaysOnTop: Bool
    @Published private(set) var automaticUpdateChecks: Bool
    @Published private(set) var textScale: Double
    @Published private(set) var barThickness: Double
    @Published private(set) var cornerRadius: Double
    @Published private(set) var compactLayout: CompactLayout
    @Published private(set) var codexAccentHex: String
    @Published private(set) var claudeAccentHex: String
    @Published private(set) var claudeLiveUsageEnabled: Bool

    var changed: ((AppSettingsChange) -> Void)?

    private let defaults: UserDefaults
    private enum Key {
        static let legacyPollingInterval = "pollingInterval"
        static let codexPollingInterval = "codexPollingInterval"
        static let claudePollingInterval = "claudePollingInterval"
        static let showCodex = "showCodex"
        static let showClaude = "showClaude"
        static let hudOpacity = "hudOpacity"
        static let showMenuBarUsage = "showMenuBarUsage"
        static let showResetCountdown = "showResetCountdown"
        static let showRefreshCountdown = "showRefreshCountdown"
        static let lockHUD = "lockHUD"
        static let clickThrough = "clickThrough"
        static let alwaysOnTop = "alwaysOnTop"
        static let automaticUpdateChecks = "automaticUpdateChecks"
        static let textScale = "textScale"
        static let barThickness = "barThickness"
        static let cornerRadius = "cornerRadius"
        static let compactLayout = "compactLayout"
        static let codexAccentHex = "codexAccentHex"
        static let claudeAccentHex = "claudeAccentHex"
        static let claudeLiveUsageEnabled = "claudeLiveUsageEnabled"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Until v0.6.5 both providers shared one cadence under the legacy
        // key; carry a saved choice over so it survives the split. A legacy
        // 2-minute choice is not valid for Claude and falls to its default.
        let legacyInterval = defaults.double(forKey: Key.legacyPollingInterval)
        codexPollingInterval = Self.migratedInterval(
            saved: defaults.double(forKey: Key.codexPollingInterval),
            legacy: legacyInterval,
            choices: Self.codexPollingChoices,
            fallback: Self.defaultCodexPollingInterval
        )
        claudePollingInterval = Self.migratedInterval(
            saved: defaults.double(forKey: Key.claudePollingInterval),
            legacy: legacyInterval,
            choices: Self.claudePollingChoices,
            fallback: Self.defaultClaudePollingInterval
        )
        let savedShowCodex = defaults.object(forKey: Key.showCodex) == nil
            ? true
            : defaults.bool(forKey: Key.showCodex)
        let savedShowClaude = defaults.object(forKey: Key.showClaude) == nil
            ? true
            : defaults.bool(forKey: Key.showClaude)
        showCodex = !savedShowCodex && !savedShowClaude ? true : savedShowCodex
        showClaude = savedShowClaude
        let savedOpacity = defaults.double(forKey: Key.hudOpacity)
        hudOpacity = defaults.object(forKey: Key.hudOpacity) == nil
            ? 1
            : min(1, max(0.6, savedOpacity))
        showMenuBarUsage = defaults.bool(forKey: Key.showMenuBarUsage)
        showResetCountdown = defaults.object(forKey: Key.showResetCountdown) == nil
            ? true
            : defaults.bool(forKey: Key.showResetCountdown)
        showRefreshCountdown = defaults.object(forKey: Key.showRefreshCountdown) == nil
            ? true
            : defaults.bool(forKey: Key.showRefreshCountdown)
        var thresholds: [String: Int] = [:]
        for provider in ProviderKind.allCases {
            for slot in UsageAlertSlot.allCases {
                let key = Self.alertThresholdKey(provider: provider, slot: slot)
                let saved = defaults.object(forKey: key) == nil ? 20 : defaults.integer(forKey: key)
                thresholds[key] = Self.allowedAlertThresholds.contains(saved) ? saved : 20
            }
        }
        alertThresholds = thresholds
        lockHUD = defaults.bool(forKey: Key.lockHUD)
        clickThrough = defaults.bool(forKey: Key.clickThrough)
        alwaysOnTop = defaults.object(forKey: Key.alwaysOnTop) == nil
            ? true
            : defaults.bool(forKey: Key.alwaysOnTop)
        automaticUpdateChecks = defaults.object(forKey: Key.automaticUpdateChecks) == nil
            ? true
            : defaults.bool(forKey: Key.automaticUpdateChecks)
        textScale = Self.savedChoice(defaults.double(forKey: Key.textScale), choices: Self.textScaleChoices, fallback: 1)
        barThickness = Self.savedChoice(defaults.double(forKey: Key.barThickness), choices: Self.barThicknessChoices, fallback: 4)
        cornerRadius = Self.savedChoice(defaults.double(forKey: Key.cornerRadius), choices: Self.cornerRadiusChoices, fallback: 14)
        compactLayout = CompactLayout(rawValue: defaults.string(forKey: Key.compactLayout) ?? "") ?? .vertical
        let savedCodexAccent = defaults.string(forKey: Key.codexAccentHex) ?? HUDAccentPalette.codexDefault
        codexAccentHex = HUDAccentPalette.choices.contains(savedCodexAccent) ? savedCodexAccent : HUDAccentPalette.codexDefault
        let savedClaudeAccent = defaults.string(forKey: Key.claudeAccentHex) ?? HUDAccentPalette.claudeDefault
        claudeAccentHex = HUDAccentPalette.choices.contains(savedClaudeAccent) ? savedClaudeAccent : HUDAccentPalette.claudeDefault
        claudeLiveUsageEnabled = defaults.bool(forKey: Key.claudeLiveUsageEnabled)
    }

    var visibleProviderCount: Int {
        (showCodex ? 1 : 0) + (showClaude ? 1 : 0)
    }

    func setCodexPollingInterval(_ interval: TimeInterval) {
        guard Self.codexPollingChoices.contains(interval), codexPollingInterval != interval else { return }
        codexPollingInterval = interval
        defaults.set(interval, forKey: Key.codexPollingInterval)
        changed?(.polling)
    }

    func setClaudePollingInterval(_ interval: TimeInterval) {
        guard Self.claudePollingChoices.contains(interval), claudePollingInterval != interval else { return }
        claudePollingInterval = interval
        defaults.set(interval, forKey: Key.claudePollingInterval)
        changed?(.polling)
    }

    private static func migratedInterval(
        saved: Double,
        legacy: Double,
        choices: [TimeInterval],
        fallback: TimeInterval
    ) -> TimeInterval {
        if choices.contains(saved) { return saved }
        if choices.contains(legacy) { return legacy }
        return fallback
    }

    func setProvider(_ provider: ProviderKind, visible: Bool) {
        let current = provider == .codex ? showCodex : showClaude
        guard current != visible else { return }
        if !visible && visibleProviderCount == 1 { return }

        if provider == .codex {
            showCodex = visible
            defaults.set(visible, forKey: Key.showCodex)
        } else {
            showClaude = visible
            defaults.set(visible, forKey: Key.showClaude)
        }
        changed?(.providers)
    }

    func setHUDOpacity(_ opacity: Double) {
        let clamped = min(1, max(0.6, opacity))
        guard abs(hudOpacity - clamped) > 0.001 else { return }
        hudOpacity = clamped
        defaults.set(clamped, forKey: Key.hudOpacity)
        changed?(.appearance)
    }

    func setShowMenuBarUsage(_ enabled: Bool) {
        guard showMenuBarUsage != enabled else { return }
        showMenuBarUsage = enabled
        defaults.set(enabled, forKey: Key.showMenuBarUsage)
        changed?(.menuBar)
    }

    func setShowResetCountdown(_ enabled: Bool) {
        guard showResetCountdown != enabled else { return }
        showResetCountdown = enabled
        defaults.set(enabled, forKey: Key.showResetCountdown)
        changed?(.timers)
    }

    func setShowRefreshCountdown(_ enabled: Bool) {
        guard showRefreshCountdown != enabled else { return }
        showRefreshCountdown = enabled
        defaults.set(enabled, forKey: Key.showRefreshCountdown)
        changed?(.timers)
    }

    func setClaudeLiveUsageEnabled(_ enabled: Bool) {
        guard claudeLiveUsageEnabled != enabled else { return }
        claudeLiveUsageEnabled = enabled
        defaults.set(enabled, forKey: Key.claudeLiveUsageEnabled)
        changed?(.claudeLiveUsage)
    }

    static let allowedAlertThresholds = [0, 5, 10, 15, 20, 25, 30]
    static let textScaleChoices: [Double] = [0.85, 1, 1.15, 1.3]
    static let barThicknessChoices: [Double] = [3, 4, 6, 8]
    static let cornerRadiusChoices: [Double] = [10, 14, 18, 24]

    func alertThreshold(provider: ProviderKind, slot: UsageAlertSlot) -> Int {
        alertThresholds[Self.alertThresholdKey(provider: provider, slot: slot)] ?? 20
    }

    func setAlertThreshold(_ threshold: Int, provider: ProviderKind, slot: UsageAlertSlot) {
        guard Self.allowedAlertThresholds.contains(threshold) else { return }
        let key = Self.alertThresholdKey(provider: provider, slot: slot)
        guard alertThresholds[key] != threshold else { return }
        alertThresholds[key] = threshold
        defaults.set(threshold, forKey: key)
        changed?(.alerts)
    }

    private static func alertThresholdKey(provider: ProviderKind, slot: UsageAlertSlot) -> String {
        "alertThreshold.\(provider.rawValue).\(slot.rawValue)"
    }

    func setLockHUD(_ enabled: Bool) {
        guard lockHUD != enabled else { return }
        lockHUD = enabled
        defaults.set(enabled, forKey: Key.lockHUD)
        changed?(.interaction)
    }

    func setClickThrough(_ enabled: Bool) {
        guard clickThrough != enabled else { return }
        clickThrough = enabled
        defaults.set(enabled, forKey: Key.clickThrough)
        changed?(.interaction)
    }

    func setAlwaysOnTop(_ enabled: Bool) {
        guard alwaysOnTop != enabled else { return }
        alwaysOnTop = enabled
        defaults.set(enabled, forKey: Key.alwaysOnTop)
        changed?(.interaction)
    }

    func setAutomaticUpdateChecks(_ enabled: Bool) {
        guard automaticUpdateChecks != enabled else { return }
        automaticUpdateChecks = enabled
        defaults.set(enabled, forKey: Key.automaticUpdateChecks)
        changed?(.updates)
    }

    func setTextScale(_ value: Double) {
        guard Self.textScaleChoices.contains(value), textScale != value else { return }
        textScale = value
        defaults.set(value, forKey: Key.textScale)
        changed?(.sizing)
    }

    func setBarThickness(_ value: Double) {
        setAppearanceChoice(value, choices: Self.barThicknessChoices, current: &barThickness, key: Key.barThickness)
    }

    func setCornerRadius(_ value: Double) {
        setAppearanceChoice(value, choices: Self.cornerRadiusChoices, current: &cornerRadius, key: Key.cornerRadius)
    }

    func setCompactLayout(_ layout: CompactLayout) {
        guard compactLayout != layout else { return }
        compactLayout = layout
        defaults.set(layout.rawValue, forKey: Key.compactLayout)
        changed?(.layout)
    }

    func setAccent(_ hex: String, provider: ProviderKind) {
        guard HUDAccentPalette.choices.contains(hex) else { return }
        if provider == .codex {
            guard codexAccentHex != hex else { return }
            codexAccentHex = hex
            defaults.set(hex, forKey: Key.codexAccentHex)
        } else {
            guard claudeAccentHex != hex else { return }
            claudeAccentHex = hex
            defaults.set(hex, forKey: Key.claudeAccentHex)
        }
        changed?(.appearance)
    }

    private func setAppearanceChoice(
        _ value: Double,
        choices: [Double],
        current: inout Double,
        key: String
    ) {
        guard choices.contains(value), current != value else { return }
        current = value
        defaults.set(value, forKey: key)
        changed?(.appearance)
    }

    private static func savedChoice(_ value: Double, choices: [Double], fallback: Double) -> Double {
        choices.contains(value) ? value : fallback
    }
}
