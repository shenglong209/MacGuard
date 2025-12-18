// SleepMonitor.swift
// MacGuard - Anti-Theft Alarm for macOS
// Created: 2025-12-18

import Cocoa
import IOKit
import IOKit.pwr_mgt

/// Protocol for receiving sleep/wake events
protocol SleepMonitorDelegate: AnyObject {
    /// Called when lid is about to close (system going to sleep)
    func lidWillClose()
    /// Called when system wakes from sleep
    func systemDidWake()
}

/// Monitors lid close events via IOKit clamshell state and sleep notifications
class SleepMonitor {
    weak var delegate: SleepMonitorDelegate?

    private var sleepAssertionID: IOPMAssertionID = 0
    private var displayAssertionID: IOPMAssertionID = 0
    private var isDelayingSleep = false
    private var isMonitoring = false
    private var caffeinateProcess: Process?

    // Lid state monitoring
    private var lidStateTimer: Timer?
    private var lastLidClosed = false

    // MARK: - Monitoring

    /// Start monitoring sleep/wake events and prevent sleep while armed
    func startMonitoring() {
        guard !isMonitoring else { return }

        // Start caffeinate as backup sleep prevention
        preventSleepWhileArmed()

        // Start polling lid state via IOKit (works even with sleep disabled)
        startLidStateMonitoring()

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

        stopLidStateMonitoring()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        allowSleep()

        isMonitoring = false
        print("[SleepMonitor] Stopped monitoring sleep events")
    }

    // MARK: - Lid State Monitoring (IOKit)

    /// Start polling clamshell (lid) state via IOKit
    private func startLidStateMonitoring() {
        // Get initial state
        lastLidClosed = isLidClosed()
        print("[SleepMonitor] Lid state monitoring started (closed: \(lastLidClosed))")

        // Poll every 0.5 seconds for lid state changes
        lidStateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkLidState()
        }
    }

    /// Stop polling lid state
    private func stopLidStateMonitoring() {
        lidStateTimer?.invalidate()
        lidStateTimer = nil
    }

    /// Check current lid state and notify delegate on change
    private func checkLidState() {
        let currentClosed = isLidClosed()

        if currentClosed && !lastLidClosed {
            // Lid just closed
            print("[SleepMonitor] Lid closed detected (IOKit)")
            delegate?.lidWillClose()
        } else if !currentClosed && lastLidClosed {
            // Lid just opened
            print("[SleepMonitor] Lid opened detected (IOKit)")
            delegate?.systemDidWake()
        }

        lastLidClosed = currentClosed
    }

    /// Check if lid is closed using IOKit AppleClamshellState
    private func isLidClosed() -> Bool {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPMrootDomain")
        )

        guard service != IO_OBJECT_NULL else {
            return false
        }

        defer { IOObjectRelease(service) }

        if let clamshellState = IORegistryEntryCreateCFProperty(
            service,
            "AppleClamshellState" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? Bool {
            return clamshellState
        }

        return false
    }

    // MARK: - Event Handlers

    @objc private func willSleep(_ notification: Notification) {
        print("[SleepMonitor] Lid closing / sleep initiated")
        // Note: caffeinate already running from startMonitoring()
        // Notify delegate immediately
        delegate?.lidWillClose()
    }

    @objc private func didWake(_ notification: Notification) {
        print("[SleepMonitor] System woke from sleep")

        allowSleep()
        delegate?.systemDidWake()
    }

    // MARK: - Sleep Prevention

    /// Prevent sleep while alarm is armed (runs continuously)
    private func preventSleepWhileArmed() {
        guard !isDelayingSleep else { return }

        let reason = "MacGuard anti-theft alarm armed"

        // 1. Start caffeinate process (runs indefinitely until stopped)
        startCaffeinate()

        // 2. Create IOPMAssertion as backup
        var sleepID: IOPMAssertionID = 0
        let sleepSuccess = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &sleepID
        )

        if sleepSuccess == kIOReturnSuccess {
            sleepAssertionID = sleepID
            print("[SleepMonitor] System sleep prevented (IOPMAssertion)")
        }

        // 3. Prevent display sleep
        var displayID: IOPMAssertionID = 0
        let displaySuccess = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &displayID
        )

        if displaySuccess == kIOReturnSuccess {
            displayAssertionID = displayID
            print("[SleepMonitor] Display sleep prevented")
        }

        isDelayingSleep = true
        print("[SleepMonitor] Sleep prevention active while armed")
    }

    /// Start caffeinate process to prevent sleep (runs until terminated)
    private func startCaffeinate() {
        stopCaffeinate()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        // -d: prevent display sleep, -i: prevent idle sleep, -s: prevent system sleep
        // No -t flag = runs indefinitely until terminated
        process.arguments = ["-dis"]

        do {
            try process.run()
            caffeinateProcess = process
            print("[SleepMonitor] Caffeinate started (preventing sleep while armed)")
        } catch {
            print("[SleepMonitor] Failed to start caffeinate: \(error)")
        }
    }

    /// Stop caffeinate process
    private func stopCaffeinate() {
        if let process = caffeinateProcess, process.isRunning {
            process.terminate()
            print("[SleepMonitor] Caffeinate stopped")
        }
        caffeinateProcess = nil
    }

    /// Allow system to sleep normally (called when disarming)
    func allowSleep() {
        guard isDelayingSleep else { return }

        stopCaffeinate()

        if sleepAssertionID != 0 {
            IOPMAssertionRelease(sleepAssertionID)
            sleepAssertionID = 0
        }

        if displayAssertionID != 0 {
            IOPMAssertionRelease(displayAssertionID)
            displayAssertionID = 0
        }

        isDelayingSleep = false
        print("[SleepMonitor] Sleep allowed")
    }

    deinit {
        stopCaffeinate()
        stopMonitoring()
    }
}
