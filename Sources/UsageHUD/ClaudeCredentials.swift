import CryptoKit
import Foundation

enum ClaudeCredentialSource: String, Equatable {
    case scopedKeychain = "scoped-keychain"
    case legacyKeychain = "legacy-keychain"
    case credentialsFile = "credentials-file"
}

struct ClaudeCredential: Equatable {
    let accessToken: String
    let plan: String?
    let source: ClaudeCredentialSource
    var refreshToken: String?
    var scopes: [String] = []
}

enum ClaudeCredentialLocation: Equatable {
    case keychain(service: String, source: ClaudeCredentialSource)
    case file(URL)
}

enum ClaudeCredentials {
    static let legacyService = "Claude Code-credentials"
    static let keychainTimeout: TimeInterval = 3

    static func configDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        if let configured = environment["CLAUDE_CONFIG_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !configured.isEmpty {
            let expanded = NSString(string: configured).expandingTildeInPath
            if NSString(string: expanded).isAbsolutePath {
                return URL(fileURLWithPath: expanded).standardizedFileURL
            }
            return homeDirectory.appendingPathComponent(expanded, isDirectory: true).standardizedFileURL
        }
        return homeDirectory.appendingPathComponent(".claude", isDirectory: true).standardizedFileURL
    }

    static func scopedServiceName(configDirectory: URL) -> String {
        let digest = SHA256.hash(data: Data(configDirectory.path.utf8))
        let suffix = digest.prefix(4).map { String(format: "%02x", $0) }.joined()
        return "\(legacyService)-\(suffix)"
    }

    static func candidateLocations(configDirectory: URL) -> [ClaudeCredentialLocation] {
        [
            .keychain(
                service: scopedServiceName(configDirectory: configDirectory),
                source: .scopedKeychain
            ),
            .keychain(service: legacyService, source: .legacyKeychain),
            .file(configDirectory.appendingPathComponent(".credentials.json")),
        ]
    }

    static func parse(_ data: Data, source: ClaudeCredentialSource) -> ClaudeCredential? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let token = ClaudeUsageProvider.findString(key: "accessToken", in: object)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !token.isEmpty
        else { return nil }

        return ClaudeCredential(
            accessToken: token,
            plan: ClaudeUsageProvider.findString(key: "subscriptionType", in: object)?.capitalized,
            source: source,
            refreshToken: ClaudeUsageProvider.findString(key: "refreshToken", in: object)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            scopes: findScopes(in: object)
        )
    }

    static func findScopes(in value: Any) -> [String] {
        if let dictionary = value as? [String: Any] {
            if let array = dictionary["scopes"] as? [String] {
                return array.filter { !$0.isEmpty }
            }
            if let joined = dictionary["scopes"] as? String {
                return joined.split(separator: " ").map(String.init)
            }
            for nested in dictionary.values {
                let match = findScopes(in: nested)
                if !match.isEmpty { return match }
            }
        } else if let array = value as? [Any] {
            for nested in array {
                let match = findScopes(in: nested)
                if !match.isEmpty { return match }
            }
        }
        return []
    }

    static func load(
        configDirectory: URL? = nil,
        excludingAccessToken: String? = nil
    ) async throws -> ClaudeCredential {
        let directory = configDirectory ?? self.configDirectory()
        for location in candidateLocations(configDirectory: directory) {
            let data: Data?
            let source: ClaudeCredentialSource
            switch location {
            case let .keychain(service, credentialSource):
                data = try? await readKeychain(service: service)
                source = credentialSource
            case let .file(url):
                data = try? Data(contentsOf: url, options: [.mappedIfSafe])
                source = .credentialsFile
            }

            guard
                let data,
                let credential = parse(data, source: source),
                credential.accessToken != excludingAccessToken
            else { continue }
            AppLog.info("claude", "Credential resolved source=\(credential.source.rawValue)")
            return credential
        }
        throw UsageError.notLoggedIn("Sign in with `claude auth login`")
    }

    private static func readKeychain(service: String) async throws -> Data? {
        try await Task.detached(priority: .utility) {
            let account = ProcessInfo.processInfo.environment["USER"] ?? NSUserName()
            return try readKeychain(
                arguments: ["find-generic-password", "-s", service, "-a", account, "-w"]
            )
        }.value
    }

    private static func readKeychain(arguments: [String]) throws -> Data? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()

        let watchdog = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + keychainTimeout, execute: watchdog)
        process.waitUntilExit()
        watchdog.cancel()

        guard process.terminationStatus == 0 else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return data.isEmpty ? nil : data
    }
}

// Recovers from an expired access token by asking the Claude CLI to log in
// from its own stored refresh token (`claude auth login` honors
// CLAUDE_CODE_OAUTH_REFRESH_TOKEN + CLAUDE_CODE_OAUTH_SCOPES without any
// browser). The CLI owns the single-use refresh token: it performs the
// rotation under its own lock and persists the result, so Usage HUD never
// risks invalidating Claude Code's copy by rotating out-of-band.
enum ClaudeCredentialRepair {
    static let minimumAttemptInterval: TimeInterval = 15 * 60
    static let loginTimeout: TimeInterval = 30

    private static let stateLock = NSLock()
    private static var lastAttempt: Date?
    private static var isRunning = false

    static func attemptAllowed(lastAttempt: Date?, now: Date = .now) -> Bool {
        guard let lastAttempt else { return true }
        return now.timeIntervalSince(lastAttempt) >= minimumAttemptInterval
    }

    static func loginEnvironment(
        refreshToken: String,
        scopes: [String],
        base: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var environment = base
        environment["CLAUDE_CODE_OAUTH_REFRESH_TOKEN"] = refreshToken
        environment["CLAUDE_CODE_OAUTH_SCOPES"] = scopes.joined(separator: " ")
        return environment
    }

    static func repair(using credential: ClaudeCredential) async -> ClaudeCredential? {
        guard let refreshToken = credential.refreshToken, !refreshToken.isEmpty else {
            AppLog.info("claude", "Credential repair skipped: no refresh token in stored credential")
            return nil
        }
        guard !credential.scopes.isEmpty else {
            AppLog.info("claude", "Credential repair skipped: no scopes in stored credential")
            return nil
        }
        guard beginAttempt() else {
            AppLog.info("claude", "Credential repair skipped: attempted recently or already running")
            return nil
        }
        defer { endAttempt() }
        guard let binary = ExecutableLocator.find("claude") else {
            AppLog.warning("claude", "Credential repair skipped: claude CLI not found")
            return nil
        }

        AppLog.info("claude", "Credential repair started: delegating token refresh to claude CLI")
        let environment = loginEnvironment(refreshToken: refreshToken, scopes: credential.scopes)
        let succeeded = await Task.detached(priority: .utility) {
            runLogin(binary: binary, environment: environment)
        }.value
        guard succeeded else {
            AppLog.warning("claude", "Credential repair failed: claude auth login did not succeed")
            return nil
        }
        guard let repaired = try? await ClaudeCredentials.load(
            excludingAccessToken: credential.accessToken
        ) else {
            AppLog.warning("claude", "Credential repair produced no new access token")
            return nil
        }
        AppLog.info("claude", "Credential repair succeeded source=\(repaired.source.rawValue)")
        return repaired
    }

    private static func beginAttempt(now: Date = .now) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !isRunning, attemptAllowed(lastAttempt: lastAttempt, now: now) else { return false }
        isRunning = true
        lastAttempt = now
        return true
    }

    private static func endAttempt() {
        stateLock.lock()
        isRunning = false
        stateLock.unlock()
    }

    private static func runLogin(binary: String, environment: [String: String]) -> Bool {
        var mergedEnvironment = environment
        // Apps opened from Finder receive a minimal PATH. An npm-installed
        // `claude` is a script whose interpreter lives beside it, so make
        // sure the binary's own directory is searchable.
        let binaryDirectory = URL(fileURLWithPath: binary).deletingLastPathComponent().path
        let inheritedPath = mergedEnvironment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        if !inheritedPath.split(separator: ":").map(String.init).contains(binaryDirectory) {
            mergedEnvironment["PATH"] = "\(binaryDirectory):\(inheritedPath)"
        }

        let process = Process()
        let errorOutput = Pipe()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["auth", "login"]
        process.environment = mergedEnvironment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorOutput
        do {
            try process.run()
        } catch {
            AppLog.warning("claude", "Credential repair could not launch claude CLI: \(error.localizedDescription)")
            return false
        }

        let watchdog = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + loginTimeout, execute: watchdog)
        process.waitUntilExit()
        watchdog.cancel()

        guard process.terminationStatus == 0 else {
            let detail = String(
                data: errorOutput.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines).suffix(200)
            AppLog.warning(
                "claude",
                "claude auth login exited status=\(process.terminationStatus) detail=\(detail.map(String.init) ?? "<none>")"
            )
            return false
        }
        return true
    }
}
