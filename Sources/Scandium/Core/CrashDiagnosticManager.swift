// CrashDiagnosticManager.swift — On-device crash logging via signal handlers & uncaught exceptions
// Project: Scandium | Author: MeoHunter | License: GPL-3.0
//
// Writes crash info + stack trace to Documents/last_crash.txt BEFORE process terminates.
// ScandiumApp reads this file on next launch to show a Safe Mode / Crash Report screen.

import Foundation
import Darwin

// MARK: - File-global crash log FD & pre-allocated buffers (must be outside the class, async-signal-safe access)

private var crashLogFD: Int32 = -1
private let crashMaxFrames: Int32 = 64
private var crashFramesBuffer: UnsafeMutablePointer<UnsafeMutableRawPointer?>? = nil
private var crashHeaderPtr: UnsafeMutablePointer<CChar>? = nil
private var crashHeaderLen: Int = 0

// MARK: - Crash Diagnostic Manager

final class CrashDiagnosticManager {

    static let shared = CrashDiagnosticManager()

    private let launchFlagKey = "scandium_is_launching"
    private let crashFileName = "last_crash.txt"
    private let previousCrashFileName = "previous_crash.txt"

    /// Cached crash log from the previous session (preserved before last_crash.txt is truncated)
    private var previousCrashLog: String?

    private init() {}

    // MARK: - Public API

    /// Call once at the very start of app launch (before any heavy work).
    /// Preserves any crash log from the previous session, opens crash log FD (safe context),
    /// then installs signal and exception handlers.
    func install() {
        if crashFramesBuffer == nil {
            crashFramesBuffer = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: Int(crashMaxFrames))
        }
        if crashHeaderPtr == nil {
            if let ptr = strdup("=== SCANDIUM CRASH SIGNAL ===\n") {
                crashHeaderPtr = ptr
                crashHeaderLen = strlen(ptr)
            }
        }

        let dirs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        if let url = dirs.first?.appendingPathComponent(crashFileName) {
            let path = url.path
            let fm = FileManager.default

            // Preserve old crash log if it exists and has content before truncating
            if fm.fileExists(atPath: path) {
                if let attrs = try? fm.attributesOfItem(atPath: path),
                   let size = attrs[.size] as? UInt64, size > 0 {
                    if let content = try? String(contentsOf: url, encoding: .utf8),
                       !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.previousCrashLog = content
                        if let prevURL = dirs.first?.appendingPathComponent(previousCrashFileName) {
                            try? fm.removeItem(at: prevURL)
                            try? fm.copyItem(at: url, to: prevURL)
                        }
                    }
                }
            }

            if crashLogFD >= 0 {
                Darwin.close(crashLogFD)
                crashLogFD = -1
            }

            crashLogFD = path.withCString { cPath in
                Darwin.open(cPath, O_WRONLY | O_CREAT | O_TRUNC, 0o644 as mode_t)
            }
        }
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
        if let log = previousCrashLog, !log.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        let dirs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        if let prevURL = dirs.first?.appendingPathComponent(previousCrashFileName),
           let content = try? String(contentsOf: prevURL, encoding: .utf8),
           !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        return false
    }

    /// Returns true only if an actual crash log file was written by signal or exception handlers.
    var didCrashDuringLastLaunch: Bool {
        return hasPreviousCrash
    }

    /// Reads the crash log content for display in Safe Mode UI.
    func readCrashLog() -> String {
        if let log = previousCrashLog, !log.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return log
        }
        let dirs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        if let prevURL = dirs.first?.appendingPathComponent(previousCrashFileName),
           let content = try? String(contentsOf: prevURL, encoding: .utf8),
           !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return content
        }
        guard let url = crashLogURL,
              let content = try? String(contentsOf: url, encoding: .utf8),
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return AppSettings.shared.loc("Không có log crash.", "No crash logs available.")
        }
        return content
    }

    /// Reads the crash log content (alias for readCrashLog)
    func readLastCrashLog() -> String {
        return readCrashLog()
    }

    /// Deletes the crash log file.
    func deleteCrashLog() {
        previousCrashLog = nil
        let dirs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        if let dir = dirs.first {
            let prevURL = dir.appendingPathComponent(previousCrashFileName)
            try? FileManager.default.removeItem(at: prevURL)
        }
        guard let url = crashLogURL else { return }
        if crashLogFD >= 0 {
            Darwin.close(crashLogFD)
            crashLogFD = -1
        }
        try? FileManager.default.removeItem(at: url)
        let path = url.path
        crashLogFD = path.withCString { cPath in
            Darwin.open(cPath, O_WRONLY | O_CREAT | O_TRUNC, 0o644 as mode_t)
        }
    }

    /// Resets all state: deletes crash log, clears launch flag.
    func resetAll() {
        deleteCrashLog()
        UserDefaults.standard.set(false, forKey: launchFlagKey)
        UserDefaults.standard.synchronize()
    }

    /// Clears all user cache data (but not tracks/settings).
    func clearCacheData() {
        StorageManager.shared.clearCache()
    }

    // MARK: - Internal: Crash Log File URL

    private var crashLogURL: URL? {
        let dirs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return dirs.first?.appendingPathComponent(crashFileName)
    }

    // MARK: - Internal: Write Crash Info (Foundation-safe — only used in ObjC exception handler)

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
        let handler: @convention(c) (Int32) -> Void = { sig in
            if crashLogFD >= 0 {
                if let hdr = crashHeaderPtr, crashHeaderLen > 0 {
                    _ = Darwin.write(crashLogFD, hdr, crashHeaderLen)
                }
                if let buf = crashFramesBuffer {
                    let count = backtrace(buf, crashMaxFrames)
                    if count > 0 {
                        backtrace_symbols_fd(buf, count, crashLogFD)
                    }
                }
                _ = Darwin.fsync(crashLogFD)
            }
            Foundation.signal(sig, SIG_DFL)
            raise(sig)
        }

        Foundation.signal(SIGABRT, handler)
        Foundation.signal(SIGILL,  handler)
        Foundation.signal(SIGSEGV, handler)
        Foundation.signal(SIGFPE,  handler)
        Foundation.signal(SIGBUS,  handler)
        Foundation.signal(SIGPIPE, SIG_IGN)
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
