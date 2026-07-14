import Foundation

protocol UsageProviding {
    func fetch() async throws -> ProviderUsage
}

enum ExecutableLocator {
    static func find(_ name: String) -> String? {
        let fm = FileManager.default
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

        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
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
            throw UsageError.executableMissing("Codex")
        }

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

            let messages = [
                #"{"method":"initialize","id":0,"params":{"clientInfo":{"name":"usage_hud","title":"Usage HUD","version":"0.1.4"}}}"#,
                #"{"method":"initialized","params":{}}"#,
                #"{"method":"account/rateLimits/read","id":1,"params":null}"#,
            ].joined(separator: "\n") + "\n"
            input.fileHandleForWriting.write(Data(messages.utf8))

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
            while process.isRunning {
                let chunk = output.fileHandleForReading.availableData
                if chunk.isEmpty { break }
                buffer.append(chunk)

                while let newline = buffer.firstIndex(of: 0x0A) {
                    let line = buffer.subdata(in: buffer.startIndex..<newline)
                    buffer.removeSubrange(buffer.startIndex...newline)
                    guard
                        let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                        (object["id"] as? NSNumber)?.intValue == 1
                    else { continue }
                    return try Self.parseResponseObject(object)
                }
            }

            let stderr = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let cleanError = stderr
                .split(separator: "\n")
                .last
                .map(String.init) ?? "Codex did not return usage data"
            if cleanError.localizedCaseInsensitiveContains("login") {
                throw UsageError.notLoggedIn("Sign in with `codex login`")
            }
            throw UsageError.commandFailed(cleanError)
        }.value
    }

    static func parseResponseObject(_ object: [String: Any]) throws -> ProviderUsage {
        if let error = object["error"] as? [String: Any] {
            throw UsageError.requestFailed(error["message"] as? String ?? "Codex usage request failed")
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
        let credential = try await readCredential()
        guard let token = Self.findString(key: "accessToken", in: credential) else {
            throw UsageError.notLoggedIn("Sign in with `claude auth login`")
        }

        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 10
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("usage-hud/0.1.4", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UsageError.requestFailed("Claude usage request returned no response")
        }
        guard http.statusCode == 200 else {
            if http.statusCode == 401 { throw UsageError.notLoggedIn("Claude login expired; run `claude auth login`") }
            throw UsageError.requestFailed("Claude usage request failed (HTTP \(http.statusCode))")
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageError.invalidResponse("Claude returned invalid usage data")
        }

        guard let primary = Self.parseWindow(object["five_hour"], label: "5h window") else {
            throw UsageError.invalidResponse("Claude returned no subscription limits")
        }
        let weekly = Self.parseWindow(object["seven_day"], label: "7d window")
        let plan = Self.findString(key: "subscriptionType", in: credential)?.capitalized

        return ProviderUsage(
            kind: .claude,
            plan: plan,
            primary: primary,
            secondary: weekly,
            fetchedAt: .now
        )
    }

    private func readCredential() async throws -> Any {
        try await Task.detached(priority: .utility) {
            let process = Process()
            let output = Pipe()
            let errors = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
            process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
            process.standardOutput = output
            process.standardError = errors
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                throw UsageError.notLoggedIn("Sign in with `claude auth login`")
            }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            guard !data.isEmpty else { throw UsageError.invalidResponse("Claude credential is empty") }
            return try JSONSerialization.jsonObject(with: data)
        }.value
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
