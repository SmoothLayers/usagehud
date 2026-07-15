import Foundation

struct ReleaseInfo: Equatable, Decodable {
    let version: String
    let url: URL

    private enum CodingKeys: String, CodingKey {
        case version = "tag_name"
        case url = "html_url"
    }
}

enum UpdateStatus: Equatable {
    case idle
    case checking
    case upToDate(String)
    case available(ReleaseInfo)
    case failed(String)

    var displayText: String {
        switch self {
        case .idle: return "Not checked yet"
        case .checking: return "Checking GitHub…"
        case let .upToDate(version): return "Up to date · v\(version)"
        case let .available(release): return "v\(release.version) is available"
        case let .failed(message): return message
        }
    }
}

enum SemanticVersion {
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let candidateParts = components(candidate)
        let currentParts = components(current)
        let count = max(candidateParts.count, currentParts.count)
        for index in 0..<count {
            let lhs = index < candidateParts.count ? candidateParts[index] : 0
            let rhs = index < currentParts.count ? currentParts[index] : 0
            if lhs != rhs { return lhs > rhs }
        }
        return false
    }

    private static func components(_ version: String) -> [Int] {
        version
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            .split(separator: "-").first?
            .split(separator: ".")
            .map { Int($0) ?? 0 } ?? []
    }
}

enum UpdateCheckSchedule {
    static let interval: TimeInterval = 24 * 60 * 60

    static func shouldRun(lastCheck: Date?, now: Date = .now) -> Bool {
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) >= interval
    }
}

@MainActor
final class UpdateChecker: ObservableObject {
    @Published private(set) var status: UpdateStatus = .idle
    var statusChanged: ((UpdateStatus) -> Void)?

    static let latestReleaseURL = URL(
        string: "https://api.github.com/repos/SmoothLayers/usagehud/releases/latest"
    )!

    func check(currentVersion: String = AppMetadata.version) async {
        setStatus(.checking)
        var request = URLRequest(url: Self.latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("usage-hud/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let release = try JSONDecoder().decode(ReleaseInfo.self, from: data)
            let normalized = release.version.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            setStatus(
                SemanticVersion.isNewer(normalized, than: currentVersion)
                    ? .available(ReleaseInfo(version: normalized, url: release.url))
                    : .upToDate(normalized)
            )
        } catch {
            AppLog.error("updates", "Update check failed: \(error.localizedDescription)")
            setStatus(.failed("Check failed · try again"))
        }
    }

    private func setStatus(_ value: UpdateStatus) {
        status = value
        statusChanged?(value)
    }
}
