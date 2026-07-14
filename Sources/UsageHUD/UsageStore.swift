import AppKit
import Foundation

@MainActor
final class UsageStore: ObservableObject {
    @Published var codex: ProviderState = .loading
    @Published var claude: ProviderState = .loading
    @Published var isCompact = UserDefaults.standard.bool(forKey: "isCompact")
    @Published var lastRefresh: Date?
    @Published var isRefreshing = false

    var compactChanged: ((Bool) -> Void)?
    private var refreshTask: Task<Void, Never>?
    private var timer: Timer?

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        refreshTask?.cancel()
        refreshTask = Task {
            async let codexResult = Self.result(from: CodexUsageProvider())
            async let claudeResult = Self.result(from: ClaudeUsageProvider())
            let (newCodex, newClaude) = await (codexResult, claudeResult)
            guard !Task.isCancelled else { return }
            codex = newCodex
            claude = newClaude
            lastRefresh = .now
            isRefreshing = false
        }
    }

    func toggleCompact() {
        isCompact.toggle()
        UserDefaults.standard.set(isCompact, forKey: "isCompact")
        compactChanged?(isCompact)
    }

    private static func result<P: UsageProviding>(from provider: P) async -> ProviderState {
        do {
            return .loaded(try await provider.fetch())
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
