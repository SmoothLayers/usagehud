import Foundation

@main
struct ProbeProviders {
    static func main() async {
        await probe(name: "Codex", provider: CodexUsageProvider())
        await probe(name: "Claude", provider: ClaudeUsageProvider())
    }

    private static func probe<P: UsageProviding>(name: String, provider: P) async {
        do {
            let usage = try await provider.fetch()
            print("\(name): \(Int(usage.primary.remainingPercent.rounded()))% remaining, \(UsageFormatting.resetText(for: usage.primary.resetsAt))")
        } catch {
            print("\(name): \(error.localizedDescription)")
        }
    }
}
