// SW³ TextFellow — Debug Logger
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Centralized debug logging for developer mode.
// Enable: defaults write org.sw3t.TextFellow debugMode -bool YES
// Or launch with: TextFellow.app/Contents/MacOS/TextFellow --debug
//
// Logs to stderr (visible in Terminal when launched from CLI)
// and to ~/Library/Logs/TextFellow/debug.log

import Foundation
import os.log

@objc(SW3TDebugLogger)
public class DebugLogger: NSObject, @unchecked Sendable {

    @objc public static let shared = DebugLogger()

    private let enabled: Bool
    private let logFile: FileHandle?
    private let queue = DispatchQueue(label: "org.sw3t.debug-logger", qos: .utility)
    private var eventCount = 0

    private override init() {
        let args = ProcessInfo.processInfo.arguments
        let hasDebugArg = args.contains("--debug") || args.contains("-debug")
        let hasDefault = UserDefaults.standard.bool(forKey: "debugMode")
        self.enabled = hasDebugArg || hasDefault

        if enabled {
            // Create log directory and file
            let logDir = NSHomeDirectory() + "/Library/Logs/TextFellow"
            try? FileManager.default.createDirectory(atPath: logDir, withIntermediateDirectories: true)
            let logPath = logDir + "/debug.log"

            // Rotate if > 5MB
            if let attrs = try? FileManager.default.attributesOfItem(atPath: logPath),
               let size = attrs[.size] as? Int, size > 5_000_000 {
                try? FileManager.default.removeItem(atPath: logPath)
            }

            FileManager.default.createFile(atPath: logPath, contents: nil)
            self.logFile = FileHandle(forWritingAtPath: logPath)
            logFile?.seekToEndOfFile()
        } else {
            self.logFile = nil
        }

        super.init()

        if enabled {
            log("BOOT", "TextFellow debug mode active")
            log("BOOT", "PID=\(ProcessInfo.processInfo.processIdentifier)")
            log("BOOT", "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
            log("BOOT", "args=\(args.joined(separator: " "))")
        }
    }

    /// ObjC-compatible log method (for performSelector:withObject:withObject:)
    @objc(log:message:)
    public func logObjC(_ category: String, message: String) {
        log(category, message)
    }

    /// Log a debug event. Category examples: METAL, LSP, GRAMMAR, FILE, THEME, SCOPE, CMD
    @objc public func log(_ category: String, _ message: String) {
        guard enabled else { return }
        queue.async { [weak self] in
            guard let self else { return }
            self.eventCount += 1
            let ts = Self.timestamp()
            let line = "[\(ts)] [\(category)] \(message)\n"

            // stderr (visible in Terminal)
            FileHandle.standardError.write(Data(line.utf8))

            // log file
            self.logFile?.write(Data(line.utf8))
        }
    }

    /// Log with format string.
    public func log(_ category: String, format: String, _ args: CVarArg...) {
        guard enabled else { return }
        let message = String(format: format, arguments: args)
        log(category, message)
    }

    /// Whether debug mode is active.
    @objc public var isEnabled: Bool { enabled }

    /// Path to the log file.
    @objc public var logFilePath: String {
        NSHomeDirectory() + "/Library/Logs/TextFellow/debug.log"
    }

    /// Total events logged this session.
    @objc public var totalEvents: Int { eventCount }

    private static func timestamp() -> String {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss.SSS"
        return df.string(from: Date())
    }
}
