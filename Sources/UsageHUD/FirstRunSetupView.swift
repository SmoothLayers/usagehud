import SwiftUI

struct SetupEnvironmentStatus: Equatable {
    let codexPath: String?
    let claudePath: String?

    static func detect() async -> SetupEnvironmentStatus {
        await Task.detached(priority: .utility) {
            SetupEnvironmentStatus(
                codexPath: ExecutableLocator.find("codex"),
                claudePath: ExecutableLocator.find("claude")
            )
        }.value
    }
}

struct FirstRunSetupView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: UsageStore
    let requestNotifications: () async -> Bool
    let finish: () -> Void

    @State private var step = 0
    @State private var environment: SetupEnvironmentStatus?
    @State private var notificationResult: Bool?
    @State private var requestingNotifications = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.08))
            Group {
                switch step {
                case 0: detectionStep
                case 1: displayStep
                default: alertsStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider().overlay(Color.white.opacity(0.08))
            footer
        }
        .padding(22)
        .frame(width: 620, height: 500)
        .background(Color(red: 0.045, green: 0.055, blue: 0.068))
        .preferredColorScheme(.dark)
        .task { environment = await SetupEnvironmentStatus.detect() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform.path.ecg.rectangle")
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(Color(hudHex: settings.codexAccentHex))
                .frame(width: 46, height: 46)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.055)))
            VStack(alignment: .leading, spacing: 4) {
                Text("INITIALIZE USAGE HUD")
                    .font(.system(size: 14, weight: .black, design: .monospaced))
                    .tracking(1.1)
                Text("Private, local usage telemetry for your AI coding tools")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
            Spacer()
            Text("0\(step + 1) / 03")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.38))
        }
        .padding(.bottom, 18)
    }

    private var detectionStep: some View {
        SetupPage(title: "SYSTEM CHECK", detail: "Usage HUD uses your existing local CLI sign-ins. Credentials are never stored by the app.") {
            VStack(spacing: 10) {
                toolStatus(.codex, path: environment?.codexPath)
                toolStatus(.claude, path: environment?.claudePath)
                if environment == nil {
                    ProgressView("Scanning local tools…")
                        .controlSize(.small)
                        .font(.system(size: 10, design: .monospaced))
                        .padding(.top, 8)
                }
            }
        }
    }

    private var displayStep: some View {
        SetupPage(title: "CHOOSE YOUR DISPLAY", detail: "Select the providers and initial HUD layout. These can be changed later in Settings.") {
            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    providerChoice(.codex, installed: environment?.codexPath != nil)
                    providerChoice(.claude, installed: environment?.claudePath != nil)
                }
                HStack(spacing: 10) {
                    layoutChoice(title: "EXPANDED", systemImage: "rectangle.split.2x1", compact: false)
                    layoutChoice(title: "COMPACT", systemImage: "rectangle.compress.vertical", compact: true)
                }
                Toggle("Show live remaining values in the menu bar", isOn: Binding(
                    get: { settings.showMenuBarUsage },
                    set: settings.setShowMenuBarUsage
                ))
                .toggleStyle(.switch)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
            }
        }
    }

    private var alertsStep: some View {
        SetupPage(title: "STAY AHEAD OF LIMITS", detail: "Optional local notifications warn when capacity is low and when a usage window resets.") {
            VStack(spacing: 16) {
                Image(systemName: notificationResult == true ? "checkmark.circle.fill" : "bell.badge")
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(notificationResult == false ? .orange : Color(hudHex: settings.claudeAccentHex))
                Text(notificationMessage)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.62))
                    .multilineTextAlignment(.center)
                Button(requestingNotifications ? "REQUESTING…" : "ENABLE NOTIFICATIONS") {
                    requestingNotifications = true
                    Task {
                        let allowed = await requestNotifications()
                        notificationResult = allowed
                        requestingNotifications = false
                    }
                }
                .buttonStyle(SetupPrimaryButtonStyle())
                .disabled(requestingNotifications || notificationResult == true)
            }
        }
    }

    private var footer: some View {
        HStack {
            if step > 0 {
                Button("BACK") { withAnimation(.easeInOut(duration: 0.2)) { step -= 1 } }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.55))
            }
            Spacer()
            if step < 2 {
                Button("CONTINUE") { withAnimation(.easeInOut(duration: 0.2)) { step += 1 } }
                    .buttonStyle(SetupPrimaryButtonStyle())
            } else {
                Button("START USAGE HUD", action: finish)
                    .buttonStyle(SetupPrimaryButtonStyle())
            }
        }
        .padding(.top, 16)
    }

    private func toolStatus(_ provider: ProviderKind, path: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: environment == nil ? "ellipsis.circle" : (path == nil ? "xmark.circle.fill" : "checkmark.circle.fill"))
                .foregroundStyle(path == nil ? Color.orange : Color(hudHex: provider == .codex ? settings.codexAccentHex : settings.claudeAccentHex))
            VStack(alignment: .leading, spacing: 3) {
                Text(provider.displayName + " CLI")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                Text(path ?? (environment == nil ? "Checking…" : "Not found — install or sign in, then rerun setup"))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.43))
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.045)))
    }

    private func providerChoice(_ provider: ProviderKind, installed: Bool) -> some View {
        let selected = provider == .codex ? settings.showCodex : settings.showClaude
        let accent = Color(hudHex: provider == .codex ? settings.codexAccentHex : settings.claudeAccentHex)
        return Button { settings.setProvider(provider, visible: !selected) } label: {
            HStack {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                Text(provider.displayName)
                Spacer()
                Text(installed ? "READY" : "NOT FOUND")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.4))
            }
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundStyle(selected ? accent : Color.white.opacity(0.48))
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(accent.opacity(selected ? 0.1 : 0.025)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(accent.opacity(selected ? 0.5 : 0.08)))
        }
        .buttonStyle(.plain)
    }

    private func layoutChoice(title: String, systemImage: String, compact: Bool) -> some View {
        Button {
            if store.isCompact != compact { store.toggleCompact() }
        } label: {
            Label(title, systemImage: systemImage)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 10).fill(store.isCompact == compact ? Color.white.opacity(0.1) : Color.white.opacity(0.035)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(store.isCompact == compact ? 0.28 : 0.07)))
        }
        .buttonStyle(.plain)
    }

    private var notificationMessage: String {
        if notificationResult == true { return "Notifications enabled. Alert thresholds can be customized in Settings." }
        if notificationResult == false { return "Permission was not granted. You can enable notifications later in System Settings." }
        return "No usage data or credentials are included in notification requests."
    }
}

private struct SetupPage<Content: View>: View {
    let title: String
    let detail: String
    let content: Content

    init(title: String, detail: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.detail = detail
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .tracking(1)
                Text(detail)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.48))
                    .fixedSize(horizontal: false, vertical: true)
            }
            content
            Spacer(minLength: 0)
        }
        .padding(.vertical, 20)
    }
}

private struct SetupPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .black, design: .monospaced))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .foregroundStyle(Color.black.opacity(0.8))
            .background(Capsule().fill(Color(red: 0.42, green: 0.94, blue: 0.78).opacity(configuration.isPressed ? 0.72 : 1)))
    }
}
