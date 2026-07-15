import Foundation
import UserNotifications

enum UsageAlertSlot: String, CaseIterable {
    case primary
    case secondary
}

enum UsageAlertEvent: Equatable {
    case lowUsage(
        provider: ProviderKind,
        windowLabel: String,
        remainingPercent: Double,
        threshold: Double
    )
    case reset(
        provider: ProviderKind,
        windowLabel: String,
        remainingPercent: Double
    )

    var title: String {
        switch self {
        case let .lowUsage(provider, _, _, threshold):
            return "\(provider.displayName) usage is below \(Int(threshold))%"
        case let .reset(provider, _, _):
            return "\(provider.displayName) usage reset"
        }
    }

    var body: String {
        switch self {
        case let .lowUsage(_, windowLabel, remainingPercent, _),
             let .reset(_, windowLabel, remainingPercent):
            return "\(windowLabel): \(Int(remainingPercent.rounded()))% remaining"
        }
    }
}

enum UsageAlertEvaluator {
    static let lowThresholds: [Double] = [20, 10, 5]
    static let resetIncrease: Double = 20

    static func evaluate(
        provider: ProviderKind,
        windowLabel: String,
        previous: Double?,
        current: Double,
        thresholds: [Double] = lowThresholds
    ) -> UsageAlertEvent? {
        guard let previous else { return nil }

        if current - previous >= resetIncrease {
            return .reset(
                provider: provider,
                windowLabel: windowLabel,
                remainingPercent: current
            )
        }

        let crossed = thresholds.filter { previous > $0 && current <= $0 }
        guard let threshold = crossed.min() else { return nil }
        return .lowUsage(
            provider: provider,
            windowLabel: windowLabel,
            remainingPercent: current,
            threshold: threshold
        )
    }
}

final class UsageAlertTracker {
    private let defaults: UserDefaults
    private let keyPrefix = "usageAlertLastRemaining"

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func observe(
        provider: ProviderKind,
        slot: UsageAlertSlot,
        window: UsageWindow,
        thresholds: [Double] = UsageAlertEvaluator.lowThresholds,
        emitEvents: Bool = true
    ) -> UsageAlertEvent? {
        let key = "\(keyPrefix).\(provider.rawValue).\(slot)"
        let previous = defaults.object(forKey: key) == nil ? nil : defaults.double(forKey: key)
        let current = window.remainingPercent
        defaults.set(current, forKey: key)
        guard emitEvents else { return nil }
        return UsageAlertEvaluator.evaluate(
            provider: provider,
            windowLabel: window.label,
            previous: previous,
            current: current,
            thresholds: thresholds
        )
    }

    func clear() {
        for provider in ProviderKind.allCases {
            for slot in UsageAlertSlot.allCases {
                defaults.removeObject(forKey: "\(keyPrefix).\(provider.rawValue).\(slot.rawValue)")
            }
        }
    }
}

final class UsageNotificationService {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func requestPermission() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                AppLog.error("alerts", "Notification permission request failed: \(error.localizedDescription)")
                return false
            }
        @unknown default:
            return false
        }
    }

    func deliver(_ event: UsageAlertEvent) {
        let content = UNMutableNotificationContent()
        content.title = event.title
        content.body = event.body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "usage-hud-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        center.add(request) { error in
            if let error {
                AppLog.error("alerts", "Notification delivery failed: \(error.localizedDescription)")
            } else {
                AppLog.info("alerts", "Notification delivered title=\(event.title)")
            }
        }
    }
}
