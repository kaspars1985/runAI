import Foundation
import AppKit
import os

/// Vienkāršs, droši lietojams (thread-safe) žurnāls, kas raksta uz
/// ~/Library/Application Support/runAI/runAI.log un arī uz os.Logger.
final class AppLogger {

    static let shared = AppLogger()

    private let logURL: URL
    private let oldLogURL: URL
    private let osLogger: Logger
    private let queue = DispatchQueue(label: "lv.runai.applogger", qos: .utility)
    private let maxSize: UInt64 = 2 * 1024 * 1024 // 2 MB

    private let dateFormatter: DateFormatter

    private init() {
        Paths.ensureDirs()
        logURL = Paths.appSupport.appendingPathComponent("runAI.log")
        oldLogURL = Paths.appSupport.appendingPathComponent("runAI.old.log")
        osLogger = Logger(subsystem: "lv.runai.app", category: "runAI")

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        dateFormatter = df

        rotateIfNeeded()
    }

    // MARK: - Rotācija

    private func rotateIfNeeded() {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: logURL.path),
              let size = attrs[.size] as? UInt64 else {
            return
        }
        if size > maxSize {
            try? fm.removeItem(at: oldLogURL)
            try? fm.moveItem(at: logURL, to: oldLogURL)
        }
    }

    // MARK: - Rakstīšana

    private func write(level: String, _ message: String) {
        let timestamp = dateFormatter.string(from: Date())
        let line = "[\(timestamp)] [\(level)] \(message)\n"

        // os.Logger
        switch level {
        case "ERROR": osLogger.error("\(message, privacy: .public)")
        case "WARN":  osLogger.warning("\(message, privacy: .public)")
        default:      osLogger.info("\(message, privacy: .public)")
        }

        // Fails
        queue.async { [logURL] in
            let fm = FileManager.default
            if !fm.fileExists(atPath: logURL.path) {
                fm.createFile(atPath: logURL.path, contents: nil)
            }
            guard let handle = try? FileHandle(forWritingTo: logURL) else { return }
            defer { try? handle.close() }
            do {
                try handle.seekToEnd()
                if let data = line.data(using: .utf8) {
                    try handle.write(contentsOf: data)
                }
            } catch {
                // Ja rakstīšana neizdodas, klusi ignorējam.
            }
        }
    }

    // MARK: - Publiskās metodes

    static func info(_ msg: String)  { shared.write(level: "INFO", msg) }
    static func warn(_ msg: String)  { shared.write(level: "WARN", msg) }
    static func error(_ msg: String) { shared.write(level: "ERROR", msg) }
    static func flush()              { shared.queue.sync {} }

    func info(_ msg: String)  { write(level: "INFO", msg) }
    func warn(_ msg: String)  { write(level: "WARN", msg) }
    func error(_ msg: String) { write(level: "ERROR", msg) }

    // MARK: - Crash handlers

    static func installCrashHandlers() {
        NSSetUncaughtExceptionHandler { exception in
            let name = exception.name.rawValue
            let reason = exception.reason ?? "(nav iemesla)"
            let stack = exception.callStackSymbols.joined(separator: "\n")
            AppLogger.error("=== NEAPSTRĀDĀTS IZŅĒMUMS ===")
            AppLogger.error("Name: \(name)")
            AppLogger.error("Reason: \(reason)")
            AppLogger.error("Call stack:\n\(stack)")
            AppLogger.flush()
        }
    }

    // MARK: - Atklāšana Finder

    static func revealLogFile() {
        let url = Paths.appSupport.appendingPathComponent("runAI.log")
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil)
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
