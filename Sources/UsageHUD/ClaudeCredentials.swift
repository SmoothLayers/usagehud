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
            source: source
        )
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
