import Foundation
import Network

struct ClaudeLiveUsageSnapshot: Equatable {
    let fiveHour: UsageWindow?
    let sevenDay: UsageWindow?
    let receivedAt: Date
}

enum ClaudeLiveUsageParser {
    static func parse(_ data: Data, receivedAt: Date = .now) -> ClaudeLiveUsageSnapshot? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let limits = object["rate_limits"] as? [String: Any]
        else { return nil }

        let fiveHour = parseWindow(
            limits["five_hour"],
            label: "5h window",
            receivedAt: receivedAt
        )
        let sevenDay = parseWindow(
            limits["seven_day"],
            label: "7d window",
            receivedAt: receivedAt
        )
        guard fiveHour != nil || sevenDay != nil else { return nil }
        return ClaudeLiveUsageSnapshot(
            fiveHour: fiveHour,
            sevenDay: sevenDay,
            receivedAt: receivedAt
        )
    }

    static func mergedUsage(
        snapshot: ClaudeLiveUsageSnapshot,
        previous: ProviderUsage?
    ) -> ProviderUsage? {
        guard let primary = snapshot.fiveHour ?? previous?.primary else { return nil }
        return ProviderUsage(
            kind: .claude,
            plan: previous?.plan,
            primary: primary,
            secondary: snapshot.sevenDay ?? previous?.secondary,
            fetchedAt: snapshot.receivedAt,
            source: .liveSession
        )
    }

    private static func parseWindow(
        _ value: Any?,
        label: String,
        receivedAt: Date
    ) -> UsageWindow? {
        guard let dictionary = value as? [String: Any] else { return nil }
        let used = (dictionary["used_percentage"] as? NSNumber)?.doubleValue
            ?? (dictionary["utilization"] as? NSNumber)?.doubleValue
        guard
            let used,
            used.isFinite,
            let resetsAt = parseTimestamp(dictionary["resets_at"]),
            resetsAt > receivedAt
        else { return nil }
        return UsageWindow(
            label: label,
            usedPercent: used,
            resetsAt: resetsAt
        )
    }

    private static func parseTimestamp(_ value: Any?) -> Date? {
        if let number = value as? NSNumber {
            let raw = number.doubleValue
            guard raw.isFinite, raw > 0 else { return nil }
            return Date(timeIntervalSince1970: raw > 10_000_000_000 ? raw / 1_000 : raw)
        }
        guard let string = value as? String else { return nil }
        if let raw = TimeInterval(string), raw > 0 {
            return Date(timeIntervalSince1970: raw > 10_000_000_000 ? raw / 1_000 : raw)
        }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }
}

enum ClaudeStatusLineInstallResult: Equatable {
    case installed
    case alreadyInstalled
    case chainedCCStatusLine
    case userStatusLinePresent
    case userOptedOut

    var detail: String {
        switch self {
        case .installed, .alreadyInstalled:
            return "Live Claude updates enabled"
        case .chainedCCStatusLine:
            return "Live Claude updates enabled alongside ccstatusline"
        case .userStatusLinePresent:
            return "Custom Claude status line detected; OAuth polling remains active"
        case .userOptedOut:
            return "Claude status line was removed; toggle this setting off and on to restore it"
        }
    }
}

struct ClaudeStatusLineInstaller {
    let settingsURL: URL
    let scriptURL: URL
    let markerURL: URL
    let endpointURL: URL
    let originalStatusLineURL: URL

    init(
        configDirectory: URL = ClaudeCredentials.configDirectory(),
        applicationSupportDirectory: URL? = nil
    ) {
        let support = applicationSupportDirectory
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/Usage HUD", isDirectory: true)
        settingsURL = configDirectory.appendingPathComponent("settings.json")
        scriptURL = support.appendingPathComponent("claude-statusline-usage-hud.sh")
        markerURL = support.appendingPathComponent("claude-statusline-usage-hud.installed")
        endpointURL = support.appendingPathComponent("claude-live-endpoint")
        originalStatusLineURL = support.appendingPathComponent("claude-statusline-original.json")
    }

    func install() throws -> ClaudeStatusLineInstallResult {
        let manager = FileManager.default
        let settings = try readSettings()
        let ownership = Self.statusLineOwnership(in: settings, managedScriptName: scriptURL.lastPathComponent)
        if ownership == .empty, manager.fileExists(atPath: markerURL.path) { return .userOptedOut }
        let originalStatusLine: [String: Any]?
        if ownership == .user {
            guard
                let statusLine = settings["statusLine"] as? [String: Any],
                let command = statusLine["command"] as? String,
                Self.isCCStatusLineCommand(command)
            else { return .userStatusLinePresent }
            originalStatusLine = statusLine
            try writeOriginalStatusLine(statusLine)
        } else {
            originalStatusLine = try readOriginalStatusLine()
        }

        try manager.createDirectory(at: scriptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(scriptContents().utf8).write(to: scriptURL, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)

        var updated = settings
        var managedStatusLine = (settings["statusLine"] as? [String: Any]) ?? [:]
        managedStatusLine["type"] = "command"
        managedStatusLine["command"] = managedCommand(
            originalCommand: originalStatusLine?["command"] as? String
        )
        updated["statusLine"] = managedStatusLine
        try writeSettings(updated, createBackup: ownership != .managed)
        try Data().write(to: markerURL, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: markerURL.path)
        if ownership == .managed { return .alreadyInstalled }
        return originalStatusLine == nil ? .installed : .chainedCCStatusLine
    }

    func uninstall() throws {
        let manager = FileManager.default
        var settings = try readSettings()
        if Self.statusLineOwnership(in: settings, managedScriptName: scriptURL.lastPathComponent) == .managed {
            if let original = try readOriginalStatusLine() {
                settings["statusLine"] = original
            } else {
                settings.removeValue(forKey: "statusLine")
            }
            try writeSettings(settings, createBackup: false)
        }
        try? manager.removeItem(at: scriptURL)
        try? manager.removeItem(at: markerURL)
        try? manager.removeItem(at: originalStatusLineURL)
    }

    enum Ownership: Equatable {
        case empty
        case managed
        case user
    }

    static func statusLineOwnership(
        in settings: [String: Any],
        managedScriptName: String = "claude-statusline-usage-hud.sh"
    ) -> Ownership {
        guard
            let statusLine = settings["statusLine"] as? [String: Any],
            let command = statusLine["command"] as? String,
            !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return .empty }
        return command.contains(managedScriptName) ? .managed : .user
    }

    static func isCCStatusLineCommand(_ command: String) -> Bool {
        command.range(
            of: #"(^|\s)ccstatusline(@[^\s]+)?($|\s)"#,
            options: .regularExpression
        ) != nil
    }

    private func readSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return [:] }
        let data = try Data(contentsOf: settingsURL)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageError.invalidResponse("Claude settings.json is not a JSON object")
        }
        return object
    }

    private func writeSettings(_ settings: [String: Any], createBackup: Bool) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if createBackup, manager.fileExists(atPath: settingsURL.path) {
            let backup = settingsURL.appendingPathExtension("usage-hud-backup")
            if !manager.fileExists(atPath: backup.path) {
                try manager.copyItem(at: settingsURL, to: backup)
            }
        }
        let data = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try data.write(to: settingsURL, options: .atomic)
    }

    private func writeOriginalStatusLine(_ statusLine: [String: Any]) throws {
        let manager = FileManager.default
        try manager.createDirectory(
            at: originalStatusLineURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(
            withJSONObject: statusLine,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try data.write(to: originalStatusLineURL, options: .atomic)
        try manager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: originalStatusLineURL.path
        )
    }

    private func readOriginalStatusLine() throws -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: originalStatusLineURL.path) else { return nil }
        let data = try Data(contentsOf: originalStatusLineURL)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageError.invalidResponse("Saved Claude status line is not a JSON object")
        }
        return object
    }

    private func managedCommand(originalCommand: String?) -> String {
        let script = Self.shellQuote(scriptURL.path)
        guard let originalCommand, !originalCommand.isEmpty else { return script }
        return "\(script) \(Self.shellQuote(originalCommand))"
    }

    private func scriptContents() -> String {
        let endpoint = Self.shellQuote(endpointURL.path)
        return """
        #!/bin/sh
        original_command=${1-}
        payload=
        while IFS= read -r usage_hud_line || [ -n "$usage_hud_line" ]; do
          payload="${payload}${usage_hud_line}\n"
        done
        payload=${payload%?}
        forward_usage_hud() {
          case "$payload" in
            *'"rate_limits"'*) ;;
            *) return ;;
          esac
          endpoint=\(endpoint)
          [ -r "$endpoint" ] || return
          . "$endpoint" 2>/dev/null || return
          [ -n "$USAGE_HUD_CLAUDE_PORT" ] || return
          [ -n "$USAGE_HUD_CLAUDE_TOKEN" ] || return
          stamp="${TMPDIR:-/tmp}/usage-hud-claude-statusline-${PPID}"
          now=$(date +%s 2>/dev/null) || now=
          if [ -n "$now" ] && [ -r "$stamp" ]; then
            IFS= read -r previous <"$stamp" 2>/dev/null || previous=
            case "$previous" in
              ''|*[!0-9]*) ;;
              *) [ $((now - previous)) -lt 15 ] && return ;;
            esac
          fi
          [ -n "$now" ] && printf '%s' "$now" >"$stamp" 2>/dev/null
          printf '%s' "$payload" | /usr/bin/curl -sS -X POST \
            "http://127.0.0.1:${USAGE_HUD_CLAUDE_PORT}/claude" \
            --connect-timeout 0.5 --max-time 1.5 \
            -H "Content-Type: application/json" \
            -H "X-Usage-HUD-Token: ${USAGE_HUD_CLAUDE_TOKEN}" \
            --data-binary @- >/dev/null 2>&1 || true
        }
        forward_usage_hud
        if [ -n "$original_command" ]; then
          printf '%s' "$payload" | /bin/sh -lc "$original_command"
        fi
        exit 0
        """
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

final class ClaudeLiveUsageServer {
    private let endpointURL: URL
    private let queue = DispatchQueue(label: "com.smoothlayers.usagehud.claude-live")
    private let token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
    private var listener: NWListener?
    private var receiveSnapshot: ((ClaudeLiveUsageSnapshot) -> Void)?

    init(endpointURL: URL) {
        self.endpointURL = endpointURL
    }

    func start(receiveSnapshot: @escaping (ClaudeLiveUsageSnapshot) -> Void) throws {
        guard listener == nil else { return }
        try? FileManager.default.removeItem(at: endpointURL)
        self.receiveSnapshot = receiveSnapshot
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            guard let self else { return }
            switch state {
            case .ready:
                guard let port = listener?.port?.rawValue else { return }
                do {
                    try self.writeEndpoint(port: port)
                    AppLog.info("claude-live", "Listener ready port=\(port)")
                } catch {
                    AppLog.error("claude-live", "Could not publish local endpoint: \(error.localizedDescription)")
                    self.stop()
                }
            case let .failed(error):
                AppLog.error("claude-live", "Listener failed: \(error.localizedDescription)")
                self.stop()
            default:
                break
            }
        }
        listener.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        receiveSnapshot = nil
        if let contents = try? String(contentsOf: endpointURL, encoding: .utf8),
           contents.contains("USAGE_HUD_CLAUDE_TOKEN=\(token)\n") {
            try? FileManager.default.removeItem(at: endpointURL)
        }
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 32 * 1_024) { [weak self] data, _, complete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var accumulated = buffer
            if let data { accumulated.append(data) }
            if accumulated.count > 128 * 1_024 {
                self.respond(413, connection: connection)
                return
            }
            if self.handleIfComplete(accumulated, connection: connection) { return }
            if complete || error != nil {
                connection.cancel()
                return
            }
            self.receive(on: connection, buffer: accumulated)
        }
    }

    private func handleIfComplete(_ request: Data, connection: NWConnection) -> Bool {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerRange = request.range(of: separator) else { return false }
        let headerData = request[..<headerRange.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            respond(400, connection: connection)
            return true
        }
        let lines = headerText.components(separatedBy: "\r\n")
        guard lines.first == "POST /claude HTTP/1.1" else {
            respond(404, connection: connection)
            return true
        }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }
        guard headers["x-usage-hud-token"] == token else {
            respond(401, connection: connection)
            return true
        }
        guard let length = headers["content-length"].flatMap(Int.init), length >= 0, length <= 64 * 1_024 else {
            respond(400, connection: connection)
            return true
        }
        let bodyStart = headerRange.upperBound
        guard request.count >= bodyStart + length else { return false }
        let body = request.subdata(in: bodyStart..<(bodyStart + length))
        guard let snapshot = ClaudeLiveUsageParser.parse(body) else {
            respond(204, connection: connection)
            return true
        }
        DispatchQueue.main.async { [weak self] in self?.receiveSnapshot?(snapshot) }
        respond(204, connection: connection)
        return true
    }

    private func respond(_ status: Int, connection: NWConnection) {
        let reason: String
        switch status {
        case 204: reason = "No Content"
        case 400: reason = "Bad Request"
        case 401: reason = "Unauthorized"
        case 404: reason = "Not Found"
        case 413: reason = "Payload Too Large"
        default: reason = "Error"
        }
        let response = Data("HTTP/1.1 \(status) \(reason)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }

    private func writeEndpoint(port: UInt16) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: endpointURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let contents = "USAGE_HUD_CLAUDE_PORT=\(port)\nUSAGE_HUD_CLAUDE_TOKEN=\(token)\n"
        let temporary = endpointURL.deletingLastPathComponent()
            .appendingPathComponent(".claude-live-endpoint-\(UUID().uuidString)")
        guard manager.createFile(
            atPath: temporary.path,
            contents: Data(contents.utf8),
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw UsageError.requestFailed("Could not create the protected Claude endpoint file")
        }
        do {
            if manager.fileExists(atPath: endpointURL.path) {
                _ = try manager.replaceItemAt(endpointURL, withItemAt: temporary)
            } else {
                try manager.moveItem(at: temporary, to: endpointURL)
            }
        } catch {
            try? manager.removeItem(at: temporary)
            throw error
        }
    }
}
