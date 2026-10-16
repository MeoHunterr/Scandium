// CrashDiagnosticManager.swift — On-device crash logging via signal handlers & uncaught exceptions
// Project: Scandium | Author: MeoHunter | License: GPL-3.0
//
// Writes crash info + stack trace to Documents/last_crash.txt BEFORE process terminates.
// ScandiumApp reads this file on next launch to show a Safe Mode / Crash Report screen.

import Foundation

// MARK: - Crash Diagnostic Manager

final class CrashDiagnosticManager {

    static let shared = CrashDiagnosticManager()

    private let launchFlagKey = "scandium_is_launching"
    private let crashFileName = "last_crash.txt"

    private init() {}

    // MARK: - Public API

    /// Call once at the very start of app launch (before any heavy work).
    /// Installs signal handlers and exception handler.
    func install() {
        installSignalHandlers()
        installExceptionHandler()
    }

    /// Mark that the app is currently launching. Call right before mounting MainContainerView.
    func markLaunchStarted() {
        // No-op to avoid false positives when app is killed or suspended
    }

    /// Mark that the UI is stable.
    func markLaunchSucceeded() {
        deleteCrashLog()
    }

    /// Returns true if a crash log from the previous session exists.
    var hasPreviousCrash: Bool {
        let url = crashLogURL
        guard let url = url else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Returns true only if an actual crash log file was written by signal or exception handlers.
    var didCrashDuringLastLaunch: Bool {
        return hasPreviousCrash
    }

    /// Reads the crash log content for display in Safe Mode UI.
    func readCrashLog() -> String {
        guard let url = crashLogURL,
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return AppSettings.shared.loc("Không có log crash.", "No crash logs available.")
        }
        return content
    }

    /// Deletes the crash log file.
    func deleteCrashLog() {
        guard let url = crashLogURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Resets all state: deletes crash log, clears launch flag.
    func resetAll() {
        deleteCrashLog()
        UserDefaults.standard.set(false, forKey: launchFlagKey)
        UserDefaults.standard.synchronize()
    }

    /// Clears all user cache data (but not tracks/settings).
    func clearCacheData() {
        URLCache.shared.removeAllCachedResponses()
        let tmpDir = NSTemporaryDirectory()
        if let files = try? FileManager.default.contentsOfDirectory(atPath: tmpDir) {
            for f in files {
                try? FileManager.default.removeItem(atPath: (tmpDir as NSString).appendingPathComponent(f))
            }
        }
    }

    // MARK: - Internal: Crash Log File URL

    private var crashLogURL: URL? {
        let dirs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return dirs.first?.appendingPathComponent(crashFileName)
    }

    // MARK: - Internal: Write Crash Info

    fileprivate static func writeCrashInfo(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let stack = Thread.callStackSymbols.prefix(40).joined(separator: "\n")
        let content = """
        ===== SCANDIUM CRASH REPORT =====
        Time: \(timestamp)
        Reason: \(message)

        --- Call Stack ---
        \(stack)
        =================================
        """

        let dirs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        if let url = dirs.first?.appendingPathComponent("last_crash.txt") {
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
        UserDefaults.standard.set(false, forKey: "scandium_is_launching")
        UserDefaults.standard.synchronize()
    }

    // MARK: - Signal Handlers

    private func installSignalHandlers() {
        let handler: @convention(c) (Int32) -> Void = { signal in
            let name: String
            switch signal {
            case SIGABRT:  name = "SIGABRT (Abort)"
            case SIGILL:   name = "SIGILL (Illegal Instruction)"
            case SIGSEGV:  name = "SIGSEGV (Segmentation Fault)"
            case SIGFPE:   name = "SIGFPE (Floating Point Exception)"
            case SIGBUS:   name = "SIGBUS (Bus Error)"
            case SIGPIPE:  name = "SIGPIPE (Broken Pipe)"
            case SIGTRAP:  name = "SIGTRAP (Trace/Breakpoint Trap)"
            default:       name = "Signal \(signal)"
            }
            CrashDiagnosticManager.writeCrashInfo("Fatal Signal: \(name)")
            // Re-raise so the system can generate a proper crash report
            Foundation.signal(signal, SIG_DFL)
            raise(signal)
        }

        Foundation.signal(SIGABRT, handler)
        Foundation.signal(SIGILL,  handler)
        Foundation.signal(SIGSEGV, handler)
        Foundation.signal(SIGFPE,  handler)
        Foundation.signal(SIGBUS,  handler)
        Foundation.signal(SIGPIPE, handler)
        Foundation.signal(SIGTRAP, handler)
    }

    private func installExceptionHandler() {
        NSSetUncaughtExceptionHandler { exception in
            let reason = exception.reason ?? "Unknown reason"
            let name = exception.name.rawValue
            CrashDiagnosticManager.writeCrashInfo("NSException: \(name) — \(reason)")
        }
    }
}
