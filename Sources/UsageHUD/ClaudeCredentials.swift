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

    // Claude Code stores several token sets in one JSON document: the
    // `claudeAiOauth` login plus an `mcpOAuth` entry per OAuth-backed MCP
    // server, all using the same `accessToken`/`refreshToken` key names. Only
    // the `claudeAiOauth` section is valid for the usage API, so never search
    // the document recursively for a token.
    static func parse(_ data: Data, source: ClaudeCredentialSource) -> ClaudeCredential? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let section: [String: Any]
        if let claudeAi = object["claudeAiOauth"] as? [String: Any] {
            section = claudeAi
        } else if object["mcpOAuth"] == nil {
            // Older flat layout: the login fields sit at the top level.
            section = object
        } else {
            return nil
        }
        guard
            let token = (section["accessToken"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !token.isEmpty
        else { return nil }

        return ClaudeCredential(
            accessToken: token,
            plan: (section["subscriptionType"] as? String)?.capitalized,
            source: source
        )
    }

    /// Shown when Claude Code's credential document exists but no longer
    /// carries a `claudeAiOauth` login. Only a fresh `/login` fixes this;
    /// merely opening Claude Code will not.
    static let signedOutMessage = "Claude Code is signed out · run /login in Claude Code"
    static let missingMessage = "Sign in with `claude auth login`"

    static func isSignedOut(_ error: Error) -> Bool {
        guard case let UsageError.notLoggedIn(message) = error else { return false }
        return message == signedOutMessage
    }

    enum LocationOutcome: Equatable {
        case resolved
        case missing
        case readFailed(status: Int32)
        case timedOut
        case malformed
        /// A JSON document was read but had no usable login block.
        case signedOut(shape: String)
        case excluded

        var logValue: String {
            switch self {
            case .resolved: return "resolved"
            case .missing: return "missing"
            case let .readFailed(status): return "read-failed(exit \(status))"
            case .timedOut: return "timed-out"
            case .malformed: return "malformed"
            case let .signedOut(shape): return "signed-out(\(shape))"
            case .excluded: return "excluded"
            }
        }
    }

    /// Keys-only description of a credential document for diagnostics.
    /// Never includes values, so it is safe to write to the app log.
    static func shape(of data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            return "not-json bytes=\(data.count)"
        }
        guard let dictionary = object as? [String: Any] else {
            return "not-object"
        }
        let topLevel = dictionary.keys.sorted().joined(separator: ",")
        guard let login = dictionary["claudeAiOauth"] as? [String: Any] else {
            return "keys=[\(topLevel)] claudeAiOauth=missing"
        }
        let loginKeys = login.keys.sorted().joined(separator: ",")
        let token = (login["accessToken"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return "keys=[\(topLevel)] claudeAiOauth=[\(loginKeys)] accessToken=\(token.isEmpty ? "empty" : "present")"
    }

    /// Picks the user-facing error once every location has been tried. A
    /// document that exists but lacks a login means Claude Code signed itself
    /// out; anything else means there is simply no credential to read.
    static func failure(for outcomes: [(ClaudeCredentialSource, LocationOutcome)]) -> UsageError {
        let signedOut = outcomes.contains {
            if case .signedOut = $0.1 { return true }
            return false
        }
        return .notLoggedIn(signedOut ? signedOutMessage : missingMessage)
    }

    static func load(
        configDirectory: URL? = nil,
        excludingAccessToken: String? = nil
    ) async throws -> ClaudeCredential {
        let directory = configDirectory ?? self.configDirectory()
        var outcomes: [(ClaudeCredentialSource, LocationOutcome)] = []
        for location in candidateLocations(configDirectory: directory) {
            let read: KeychainRead
            let source: ClaudeCredentialSource
            switch location {
            case let .keychain(service, credentialSource):
                read = await readKeychain(service: service)
                source = credentialSource
            case let .file(url):
                if let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) {
                    read = .data(data)
                } else {
                    read = .notFound
                }
                source = .credentialsFile
            }

            let data: Data
            switch read {
            case let .data(payload):
                data = payload
            case .notFound:
                outcomes.append((source, .missing)); continue
            case let .failed(status):
                outcomes.append((source, .readFailed(status: status))); continue
            case .timedOut:
                outcomes.append((source, .timedOut)); continue
            }

            guard let credential = parse(data, source: source) else {
                let isJSON = (try? JSONSerialization.jsonObject(with: data)) != nil
                outcomes.append((source, isJSON ? .signedOut(shape: shape(of: data)) : .malformed))
                continue
            }
            guard credential.accessToken != excludingAccessToken else {
                outcomes.append((source, .excluded)); continue
            }
            AppLog.info("claude", "Credential resolved source=\(credential.source.rawValue)")
            return credential
        }

        // Only log when no exclusion was requested: the 401 re-read path
        // expects to come up empty and would otherwise spam the log.
        if excludingAccessToken == nil {
            let summary = outcomes.map { "\($0.0.rawValue)=\($0.1.logValue)" }.joined(separator: " ")
            AppLog.warning("claude", "No usable credential: \(summary)")
        }
        throw failure(for: outcomes)
    }

    enum KeychainRead: Equatable {
        case data(Data)
        case notFound
        case failed(status: Int32)
        case timedOut
    }

    /// `security find-generic-password` exits 44 (errSecItemNotFound) when
    /// the item does not exist; any other non-zero status is a real failure.
    static let keychainItemNotFoundStatus: Int32 = 44

    private static func readKeychain(service: String) async -> KeychainRead {
        await Task.detached(priority: .utility) {
            let account = ProcessInfo.processInfo.environment["USER"] ?? NSUserName()
            return readKeychain(
                arguments: ["find-generic-password", "-s", service, "-a", account, "-w"]
            )
        }.value
    }

    private static func readKeychain(arguments: [String]) -> KeychainRead {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return .failed(status: -1)
        }

        let timedOut = LockedFlag()
        let watchdog = DispatchWorkItem {
            if process.isRunning {
                timedOut.set()
                process.terminate()
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + keychainTimeout, execute: watchdog)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()

        if timedOut.value { return .timedOut }
        switch process.terminationStatus {
        case 0:
            return data.isEmpty ? .notFound : .data(data)
        case keychainItemNotFoundStatus:
            return .notFound
        case let status:
            return .failed(status: status)
        }
    }
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false

    var value: Bool {
        lock.lock(); defer { lock.unlock() }
        return flag
    }

    func set() {
        lock.lock(); defer { lock.unlock() }
        flag = true
    }
}
