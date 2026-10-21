// SleepMonitor.swift
// MacGuard - Anti-Theft Alarm for macOS
// Created: 2025-12-18

import Cocoa
import IOKit
import IOKit.pwr_mgt

/// Monitors lid close events via IOKit clamshell state and sleep notifications,
/// and keeps the Mac awake for as long as it is monitoring.
class SleepMonitor {
    var onInput: (AlarmInput) -> Void = { _ in }

    private struct Session {
        let caffeinate: Process?
        let assertions: [IOPMAssertionID]
        let lidTimer: Timer
        var lidClosed: Bool
    }

    /// Sleep prevention lives exactly as long as monitoring, so a wake can't
    /// release it while armed.
    private var session: Session?

    // MARK: - Monitoring

    func startMonitoring() {
        guard session == nil else { return }

        // Polled via IOKit: works even with sleep disabled. Common modes: a
        // default-mode timer pauses while a menu is open.
        let lidTimer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkLidState()
        }
        RunLoop.main.add(lidTimer, forMode: .common)

        let lidClosed = Self.isLidClosed
        session = Session(caffeinate: Self.startCaffeinate(), assertions: Self.preventSleep(),
                          lidTimer: lidTimer, lidClosed: lidClosed)
        logActivity(.system, "Sleep prevention active while armed")
        logActivity(.system, "Lid state monitoring started (closed: \(lidClosed))")

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        logActivity(.system, "Started monitoring sleep events")
    }

    func stopMonitoring() {
        guard let session else { return }
        session.lidTimer.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        if let caffeinate = session.caffeinate, caffeinate.isRunning {
            caffeinate.terminate()
            logActivity(.system, "Caffeinate stopped")
        }
        session.assertions.forEach { IOPMAssertionRelease($0) }
        self.session = nil
        logActivity(.system, "Sleep allowed")
        logActivity(.system, "Stopped monitoring sleep events")
    }

    // MARK: - Lid State

    private func checkLidState() {
        guard let wasClosed = session?.lidClosed else { return }
        let closed = Self.isLidClosed
        guard closed != wasClosed else { return }
        session?.lidClosed = closed
        if closed {
            logActivity(.system, "Lid closed detected (IOKit)")
            onInput(.severeIntrusion(.lidClosed))
        } else {
            logActivity(.system, "Lid opened detected (IOKit)")
            onInput(.systemWoke)
        }
    }

    private static var isLidClosed: Bool {
        IORegistry.property("AppleClamshellState", ofServiceMatching: "IOPMrootDomain") ?? false
    }

    // MARK: - Event Handlers

    @objc private func willSleep(_ notification: Notification) {
        logActivity(.system, "Lid closing / sleep initiated")
        onInput(.severeIntrusion(.lidClosed))
    }

    @objc private func didWake(_ notification: Notification) {
        logActivity(.system, "System woke from sleep")
        onInput(.systemWoke)
    }

    // MARK: - Sleep Prevention

    /// Backup to the power assertions.
    private static func startCaffeinate() -> Process? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        // -d display, -i idle, -s system sleep; no -t, so it runs until terminated
        process.arguments = ["-dis"]
        do {
            try process.run()
            logActivity(.system, "Caffeinate started (preventing sleep while armed)")
            return process
        } catch {
            logActivity(.system, "Failed to start caffeinate: \(error)")
            return nil
        }
    }

    private static func preventSleep() -> [IOPMAssertionID] {
        [kIOPMAssertionTypePreventSystemSleep, kIOPMAssertionTypeNoDisplaySleep].compactMap { type in
            var id = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                     "MacGuard anti-theft alarm armed" as CFString, &id)
            return result == kIOReturnSuccess ? id : nil
        }
    }

    deinit {
        stopMonitoring()
    }
}
