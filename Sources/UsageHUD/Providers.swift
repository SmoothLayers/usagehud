import Foundation

protocol UsageProviding {
    func fetch() async throws -> ProviderUsage
}

enum ExecutableLocator {
    private static let cacheLock = NSLock()
    private static var cache: [String: String] = [:]

    static func find(_ name: String) -> String? {
        let fm = FileManager.default
        cacheLock.lock()
        let cached = cache[name]
        cacheLock.unlock()
        if let cached, fm.isExecutableFile(atPath: cached) { return cached }

        guard let resolved = resolve(name, fm: fm) else { return nil }
        cacheLock.lock()
        cache[name] = resolved
        cacheLock.unlock()
        return resolved
    }

    private static func resolve(_ name: String, fm: FileManager) -> String? {
        let home = fm.homeDirectoryForCurrentUser.path
        let fixedCandidates = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "\(home)/.local/bin/\(name)",
        ]

        for path in fixedCandidates where fm.isExecutableFile(atPath: path) {
            return path
        }

        let nvmRoot = "\(home)/.nvm/versions/node"
        if let versions = try? fm.contentsOfDirectory(atPath: nvmRoot) {
            for version in versions.sorted().reversed() {
                let path = "\(nvmRoot)/\(version)/bin/\(name)"
                if fm.isExecutableFile(atPath: path) { return path }
            }
        }

        // Ask the user's own login shell so PATH additions in bash or fish
        // configs are honored, not just zsh's.
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-lc", "command -v \(name)"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let value = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.flatMap { fm.isExecutableFile(atPath: $0) ? $0 : nil }
    }
}

struct CodexUsageProvider: UsageProviding {
    func fetch() async throws -> ProviderUsage {
        guard let binary = ExecutableLocator.find("codex") else {
            AppLog.error("codex", "Codex CLI not found")
            throw UsageError.executableMissing("Codex")
        }

        AppLog.info("codex", "Usage request started")

        return try await Task.detached(priority: .utility) {
            let process = Process()
            let input = Pipe()
            let output = Pipe()
            let errors = Pipe()
            process.executableURL = URL(fileURLWithPath: binary)
            process.arguments = ["app-server", "--stdio"]
            // Apps opened from Finder receive a minimal PATH. NVM's `codex`
            // launcher uses `#!/usr/bin/env node`, so include the directory
            // that contains both the launcher and its Node runtime.
            var environment = ProcessInfo.processInfo.environment
            let binaryDirectory = URL(fileURLWithPath: binary)
                .deletingLastPathComponent()
                .path
            let inheritedPath = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
            let pathParts = inheritedPath.split(separator: ":").map(String.init)
            environment["PATH"] = pathParts.contains(binaryDirectory)
                ? inheritedPath
                : "\(binaryDirectory):\(inheritedPath)"
            process.environment = environment
            process.standardInput = input
            process.standardOutput = output
            process.standardError = errors

            try process.run()

            let initialize = #"{"jsonrpc":"2.0","method":"initialize","id":0,"params":{"clientInfo":{"name":"usage_hud","title":"Usage HUD","version":"\#(AppMetadata.version)"}}}"# + "\n"
            input.fileHandleForWriting.write(Data(initialize.utf8))

            let watchdog = DispatchWorkItem {
                if process.isRunning { process.terminate() }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 10, execute: watchdog)
            defer {
                watchdog.cancel()
                try? input.fileHandleForWriting.close()
                if process.isRunning { process.terminate() }
            }

            // Keep stdin open while app-server performs its asynchronous account
            // lookup. Closing it immediately can cancel the request before the
            // rate-limit snapshot is populated.
            var buffer = Data()
            var rateLimitRequestSent = false
            while process.isRunning {
                let chunk = output.fileHandleForReading.availableData
                if chunk.isEmpty { break }
                buffer.append(chunk)

                while let newline = buffer.firstIndex(of: 0x0A) {
                    let line = buffer.subdata(in: buffer.startIndex..<newline)
                    buffer.removeSubrange(buffer.startIndex...newline)
                    guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                        continue
                    }
                    let responseID = (object["id"] as? NSNumber)?.intValue
                    if responseID == 0, !rateLimitRequestSent {
                        if let error = object["error"] as? [String: Any] {
                            let rpcError = UsageError.requestFailed(error["message"] as? String ?? "Codex initialization failed")
                            if process.isRunning { process.terminate() }
                            AppLog.warning("codex", "App-server initialization failed; trying read-only CLI status fallback")
                            return try Self.fetchViaStatusCLI(binary: binary, environment: environment, originalError: rpcError)
                        }
                        let followUp = [
                            #"{"jsonrpc":"2.0","method":"initialized","params":{}}"#,
                            #"{"jsonrpc":"2.0","method":"account/rateLimits/read","id":1,"params":{}}"#,
                        ].joined(separator: "\n") + "\n"
                        input.fileHandleForWriting.write(Data(followUp.utf8))
                        rateLimitRequestSent = true
                        continue
                    }
                    guard responseID == 1 else { continue }
                    do {
                        let usage = try Self.parseResponseObject(object)
                        AppLog.info("codex", "Usage request succeeded remaining=\(Int(usage.primary.remainingPercent.rounded()))% window=\(usage.primary.label)")
                        return usage
                    } catch let error as UsageError {
                        if case UsageError.notLoggedIn = error { throw error }
                        if process.isRunning { process.terminate() }
                        AppLog.warning("codex", "App-server usage request failed; trying read-only CLI status fallback")
                        return try Self.fetchViaStatusCLI(binary: binary, environment: environment, originalError: error)
                    }
                }
            }

            let stderr = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let cleanError = stderr
                .split(separator: "\n")
                .last
                .map(String.init) ?? "Codex did not return usage data"
            if cleanError.localizedCaseInsensitiveContains("login") {
                AppLog.error("codex", "Usage request failed: login required")
                throw UsageError.notLoggedIn("Sign in with `codex login`")
            }
            let rpcError = UsageError.commandFailed(cleanError)
            AppLog.warning("codex", "App-server returned no usage; trying read-only CLI status fallback")
            return try Self.fetchViaStatusCLI(binary: binary, environment: environment, originalError: rpcError)
        }.value
    }

    static func parseStatusOutput(_ output: String, fetchedAt: Date = .now) -> ProviderUsage? {
        let clean = output.replacingOccurrences(
            of: "\u{001B}\\[[0-?]*[ -/]*[@-~]",
            with: "",
            options: .regularExpression
        )
        guard let primaryUsed = parsedUsedPercent(label: "5h", in: clean) else { return nil }
        let secondaryUsed = parsedUsedPercent(label: "weekly", in: clean)
        return ProviderUsage(
            kind: .codex,
            plan: nil,
            primary: UsageWindow(label: "5h window", usedPercent: primaryUsed, resetsAt: nil),
            secondary: secondaryUsed.map {
                UsageWindow(label: "7d window", usedPercent: $0, resetsAt: nil)
            },
            fetchedAt: fetchedAt,
            source: .cliFallback
        )
    }

    private static func parsedUsedPercent(label: String, in output: String) -> Double? {
        let pattern = "(?i)\(NSRegularExpression.escapedPattern(for: label))\\s+limit[^\\n\\r]*?([0-9]{1,3})%\\s*(left|used)?"
        guard
            let expression = try? NSRegularExpression(pattern: pattern),
            let match = expression.firstMatch(
                in: output,
                range: NSRange(output.startIndex..., in: output)
            ),
            let valueRange = Range(match.range(at: 1), in: output),
            let value = Double(output[valueRange])
        else { return nil }
        let suffix: String
        if match.range(at: 2).location != NSNotFound,
           let suffixRange = Range(match.range(at: 2), in: output) {
            suffix = output[suffixRange].lowercased()
        } else {
            suffix = "used"
        }
        let clamped = min(100, max(0, value))
        return suffix == "left" ? 100 - clamped : clamped
    }

    private static func fetchViaStatusCLI(
        binary: String,
        environment: [String: String],
        originalError: Error
    ) throws -> ProviderUsage {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/script")
        process.arguments = ["-q", "/dev/null", binary, "-s", "read-only", "-a", "untrusted"]
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        var fallbackEnvironment = environment
        fallbackEnvironment["TERM"] = "xterm-256color"
        process.environment = fallbackEnvironment
        process.standardInput = input
        process.standardOutput = output
        process.standardError = output
        try process.run()

        let watchdog = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 15, execute: watchdog)
        defer {
            watchdog.cancel()
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
        }

        // `script` gives the full-screen CLI a private PTY. The read-only and
        // untrusted flags ensure a fallback can inspect status but cannot act.
        Thread.sleep(forTimeInterval: 1)
        input.fileHandleForWriting.write(Data("/status\r".utf8))
        let resendStatus = DispatchWorkItem {
            if process.isRunning {
                input.fileHandleForWriting.write(Data("/status\r".utf8))
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 2, execute: resendStatus)
        defer { resendStatus.cancel() }

        var buffer = Data()
        while process.isRunning {
            let chunk = output.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            buffer.append(chunk)
            if buffer.count > 100_000 {
                buffer.removeFirst(buffer.count - 100_000)
            }
            if let text = String(data: buffer, encoding: .utf8),
               let usage = parseStatusOutput(text) {
                AppLog.info("codex", "CLI status fallback succeeded remaining=\(Int(usage.primary.remainingPercent.rounded()))%")
                return usage
            }
        }

        if let text = String(data: buffer, encoding: .utf8) {
            let normalized = text.lowercased()
            if normalized.contains("sign in") || normalized.contains("login") {
                throw UsageError.notLoggedIn("Sign in with `codex login`")
            }
        }
        AppLog.error("codex", "CLI status fallback failed; preserving app-server error")
        throw originalError
    }

    static func parseResponseObject(_ object: [String: Any]) throws -> ProviderUsage {
        if let error = object["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "Codex usage request failed"
            let normalized = message.lowercased()
            if normalized.contains("authentication required")
                || normalized.contains("not signed in")
                || normalized.contains("login required") {
                throw UsageError.notLoggedIn("Sign in with `codex login`")
            }
            throw UsageError.requestFailed(message)
        }
        guard let result = object["result"] as? [String: Any] else {
            throw UsageError.invalidResponse("Codex returned no usage response")
        }

        let legacy = result["rateLimits"] as? [String: Any]
        let buckets = result["rateLimitsByLimitId"] as? [String: Any]
        let codexBucket = buckets?["codex"] as? [String: Any]
        let firstPopulatedBucket = buckets?.values
            .compactMap { $0 as? [String: Any] }
            .first { $0["primary"] is [String: Any] }
        guard
            let snapshot = [legacy, codexBucket, firstPopulatedBucket]
                .compactMap({ $0 })
                .first(where: { $0["primary"] is [String: Any] }),
            let primary = parseWindow(snapshot["primary"], fallbackLabel: "Session")
        else {
            throw UsageError.invalidResponse("Codex returned no subscription limits")
        }

        return ProviderUsage(
            kind: .codex,
            plan: (snapshot["planType"] as? String)?.replacingOccurrences(of: "_", with: " ").capitalized,
            primary: primary,
            secondary: parseWindow(snapshot["secondary"], fallbackLabel: "Weekly"),
            fetchedAt: .now
        )
    }

    private static func parseWindow(_ value: Any?, fallbackLabel: String) -> UsageWindow? {
        guard let dictionary = value as? [String: Any] else { return nil }
        let used = (dictionary["usedPercent"] as? NSNumber)?.doubleValue ?? 0
        let duration = (dictionary["windowDurationMins"] as? NSNumber)?.intValue
        let resetSeconds = (dictionary["resetsAt"] as? NSNumber)?.doubleValue
        let label: String
        if let duration {
            if duration < 60 { label = "\(duration)m window" }
            else if duration < 1_440 { label = "\(duration / 60)h window" }
            else { label = "\(duration / 1_440)d window" }
        } else {
            label = fallbackLabel
        }
        return UsageWindow(
            label: label,
            usedPercent: used,
            resetsAt: resetSeconds.map { Date(timeIntervalSince1970: $0) }
        )
    }
}

struct ClaudeUsageProvider: UsageProviding {
    private let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    func fetch() async throws -> ProviderUsage {
        AppLog.info("claude", "Usage request started")
        var credential = try await ClaudeCredentials.load()
        var response = try await requestUsage(token: credential.accessToken)

        // Claude Code can rotate its scoped Keychain token while a poll is in
        // flight. Re-read once on 401, but only retry when the token changed.
        if response.http.statusCode == 401,
           let refreshed = try? await ClaudeCredentials.load(excludingAccessToken: credential.accessToken) {
            AppLog.info("claude", "Credential rotated after HTTP 401; retrying once source=\(refreshed.source.rawValue)")
            credential = refreshed
            response = try await requestUsage(token: credential.accessToken)
        }

        let data = response.data
        let http = response.http
        AppLog.info("claude", "Usage response HTTP \(http.statusCode)")
        guard http.statusCode == 200 else {
            if http.statusCode == 401 {
                AppLog.error("claude", "Usage request failed: login expired")
                throw UsageError.notLoggedIn("Claude login expired; run `claude auth login`")
            }
            if http.statusCode == 403 {
                AppLog.error("claude", "Usage request failed: OAuth scope unavailable")
                throw UsageError.notLoggedIn("Claude login cannot read usage; run `claude auth login`")
            }
            if http.statusCode == 429 {
                let rawRetryAfter = http.value(forHTTPHeaderField: "Retry-After")
                let parsedRetryAfter = Self.parseRetryAfter(rawRetryAfter)
                AppLog.warning("claude", Self.retryAfterLogMessage(rawValue: rawRetryAfter, parsedSeconds: parsedRetryAfter))
                throw UsageError.rateLimited(retryAfter: parsedRetryAfter)
            }
            AppLog.error("claude", "Usage request failed HTTP \(http.statusCode)")
            throw UsageError.requestFailed("Claude usage request failed (HTTP \(http.statusCode))")
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageError.invalidResponse("Claude returned invalid usage data")
        }

        guard let primary = Self.parseWindow(object["five_hour"], label: "5h window") else {
            throw UsageError.invalidResponse("Claude returned no subscription limits")
        }
        let weekly = Self.parseWindow(object["seven_day"], label: "7d window")

        let usage = ProviderUsage(
            kind: .claude,
            plan: credential.plan,
            primary: primary,
            secondary: weekly,
            fetchedAt: .now,
            source: .providerAPI
        )
        AppLog.info("claude", "Usage request succeeded remaining=\(Int(usage.primary.remainingPercent.rounded()))% window=\(usage.primary.label)")
        return usage
    }

    private func requestUsage(token: String) async throws -> (data: Data, http: HTTPURLResponse) {

        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 10
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("usage-hud/\(AppMetadata.version)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            AppLog.error("claude", "Usage request returned no HTTP response")
            throw UsageError.requestFailed("Claude usage request returned no response")
        }
        return (data, http)
    }

    static func parseWindow(_ value: Any?, label: String) -> UsageWindow? {
        guard let dictionary = value as? [String: Any] else { return nil }
        guard let utilization = (dictionary["utilization"] as? NSNumber)?.doubleValue else { return nil }
        let reset: Date?
        if let resetString = dictionary["resets_at"] as? String {
            let fractionalFormatter = ISO8601DateFormatter()
            fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            reset = fractionalFormatter.date(from: resetString)
                ?? ISO8601DateFormatter().date(from: resetString)
        } else {
            reset = nil
        }
        return UsageWindow(label: label, usedPercent: utilization, resetsAt: reset)
    }

    static func parseRetryAfter(_ value: String?, now: Date = .now) -> TimeInterval? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        // A zero-second value can produce a tight 429 loop when the service is
        // still rate limited. Treat it as unusable so the scheduler applies its
        // conservative fallback backoff instead.
        if let seconds = TimeInterval(value), seconds > 0 { return min(seconds, 24 * 60 * 60) }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let date = formatter.date(from: value) else { return nil }
        let interval = date.timeIntervalSince(now)
        return interval > 0 ? min(interval, 24 * 60 * 60) : nil
    }

    static func retryAfterLogMessage(rawValue: String?, parsedSeconds: TimeInterval?) -> String {
        let raw = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayedRaw = raw.flatMap { $0.isEmpty ? nil : $0 } ?? "<missing>"
        let displayedSeconds = parsedSeconds.map { String(Int($0.rounded())) } ?? "<unparsed>"
        return "Rate limited HTTP 429 Retry-After raw=\"\(displayedRaw)\" parsedSeconds=\(displayedSeconds)"
    }

    static func findString(key: String, in value: Any) -> String? {
        if let dictionary = value as? [String: Any] {
            if let match = dictionary[key] as? String { return match }
            for nested in dictionary.values {
                if let match = findString(key: key, in: nested) { return match }
            }
        } else if let array = value as? [Any] {
            for nested in array {
                if let match = findString(key: key, in: nested) { return match }
            }
        }
        return nil
    }
}
