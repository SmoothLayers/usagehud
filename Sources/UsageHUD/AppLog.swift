import Foundation

enum AppMetadata {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.6.1"
    }
}

final class AppLogger: @unchecked Sendable {
    enum Level: String {
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
    }

    let fileURL: URL
    private let previousFileURL: URL
    private let maxBytes: UInt64
    private let queue = DispatchQueue(label: "com.smoothlayers.usagehud.log")
    private let formatter: ISO8601DateFormatter

    init(directory: URL, maxBytes: UInt64 = 1_000_000) {
        fileURL = directory.appendingPathComponent("usage-hud.log")
        previousFileURL = directory.appendingPathComponent("usage-hud.previous.log")
        self.maxBytes = maxBytes
        formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    @discardableResult
    func prepare() -> Bool {
        queue.sync {
            do {
                try ensureFileExists()
                return true
            } catch {
                return false
            }
        }
    }

    func log(_ level: Level, category: String, _ message: String) {
        queue.async { [self] in
            do {
                try ensureFileExists()
                let safeMessage = message
                    .replacingOccurrences(of: "\r", with: " ")
                    .replacingOccurrences(of: "\n", with: " ")
                    .replacingOccurrences(of: "\t", with: " ")
                let line = "\(formatter.string(from: .now)) [\(level.rawValue)] [\(category)] \(safeMessage)\n"
                let data = Data(line.utf8)
                try rotateIfNeeded(adding: UInt64(data.count))
                let handle = try FileHandle(forWritingTo: fileURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } catch {
                // Logging must never interfere with usage refreshes.
            }
        }
    }

    func flush() {
        queue.sync {}
    }

    @discardableResult
    func clear() -> Bool {
        queue.sync {
            do {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    try FileManager.default.removeItem(at: fileURL)
                }
                if FileManager.default.fileExists(atPath: previousFileURL.path) {
                    try FileManager.default.removeItem(at: previousFileURL)
                }
                try ensureFileExists()
                return true
            } catch {
                return false
            }
        }
    }

    private func ensureFileExists() throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try Data().write(to: fileURL, options: .atomic)
        }
    }

    private func rotateIfNeeded(adding bytes: UInt64) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let currentBytes = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        guard currentBytes + bytes > maxBytes else { return }

        if FileManager.default.fileExists(atPath: previousFileURL.path) {
            try FileManager.default.removeItem(at: previousFileURL)
        }
        try FileManager.default.moveItem(at: fileURL, to: previousFileURL)
        try Data().write(to: fileURL, options: .atomic)
    }
}

enum AppLog {
    private static let freshStartVersion = "0.1.13"
    private static let freshStartDefaultsKey = "logsClearedForVersion.0.1.13"
    private static let logger = AppLogger(
        directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Usage HUD", isDirectory: true)
    )

    static var fileURL: URL { logger.fileURL }

    @discardableResult
    static func prepare() -> Bool { logger.prepare() }
    static func clearForFreshStartIfNeeded(defaults: UserDefaults = .standard) {
        guard AppMetadata.version == freshStartVersion, !defaults.bool(forKey: freshStartDefaultsKey) else { return }
        if logger.clear() {
            defaults.set(true, forKey: freshStartDefaultsKey)
        }
    }
    static func flush() { logger.flush() }
    static func info(_ category: String, _ message: String) { logger.log(.info, category: category, message) }
    static func warning(_ category: String, _ message: String) { logger.log(.warning, category: category, message) }
    static func error(_ category: String, _ message: String) { logger.log(.error, category: category, message) }
}
