// SleepMonitor.swift
// MacGuard - Anti-Theft Alarm for macOS
// Created: 2025-12-18

import Cocoa
import IOKit.pwr_mgt

/// Protocol for receiving sleep/wake events
protocol SleepMonitorDelegate: AnyObject {
    /// Called when lid is about to close (system going to sleep)
    func lidWillClose()
    /// Called when system wakes from sleep
    func systemDidWake()
}

/// Monitors lid close (sleep) events and can delay sleep briefly for alarm
class SleepMonitor {
    weak var delegate: SleepMonitorDelegate?

    private var assertionID: IOPMAssertionID = 0
    private var isDelayingSleep = false
    private var isMonitoring = false

    // MARK: - Monitoring

    /// Start monitoring sleep/wake events
    func startMonitoring() {
        guard !isMonitoring else { return }

        let center = NSWorkspace.shared.notificationCenter

        center.addObserver(
            self,
            selector: #selector(willSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )

        center.addObserver(
            self,
            selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        isMonitoring = true
        print("[SleepMonitor] Started monitoring sleep events")
    }

    /// Stop monitoring sleep/wake events
    func stopMonitoring() {
        guard isMonitoring else { return }

        NSWorkspace.shared.notificationCenter.removeObserver(self)
        allowSleep()
        isMonitoring = false

        print("[SleepMonitor] Stopped monitoring sleep events")
    }

    // MARK: - Event Handlers

    @objc private func willSleep(_ notification: Notification) {
        print("[SleepMonitor] Lid closing / sleep initiated")

        // Delay sleep briefly to allow alarm to play
        preventSleep(reason: "MacGuard anti-theft alarm")

        // Notify delegate immediately
        delegate?.lidWillClose()
    }

    @objc private func didWake(_ notification: Notification) {
        print("[SleepMonitor] System woke from sleep")

        allowSleep()
        delegate?.systemDidWake()
    }

    // MARK: - Sleep Prevention

    /// Prevent system sleep briefly to allow alarm to trigger
    /// - Parameter reason: Description for sleep assertion
    func preventSleep(reason: String) {
        guard !isDelayingSleep else { return }

        var id: IOPMAssertionID = 0
        let success = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &id
        )

        if success == kIOReturnSuccess {
            assertionID = id
            isDelayingSleep = true
            print("[SleepMonitor] Sleep delayed for alarm")

            // Auto-release after 30 seconds (max practical delay)
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
                self?.allowSleep()
            }
        } else {
            print("[SleepMonitor] Failed to create sleep assertion")
        }
    }

    /// Allow system to sleep normally
    func allowSleep() {
        guard isDelayingSleep, assertionID != 0 else { return }

        IOPMAssertionRelease(assertionID)
        assertionID = 0
        isDelayingSleep = false

        print("[SleepMonitor] Sleep allowed")
    }

    deinit {
        stopMonitoring()
    }
}
