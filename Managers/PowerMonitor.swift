// PowerMonitor.swift
// MacGuard - Anti-Theft Alarm for macOS
// Created: 2025-12-18

import Foundation
import IOKit.ps

/// Protocol for receiving power state change events
protocol PowerMonitorDelegate: AnyObject {
    /// Called when power cable is disconnected
    func powerCableDisconnected()
    /// Called when power cable is connected
    func powerCableConnected()
}

/// Monitors power cable connect/disconnect events
class PowerMonitor {
    weak var delegate: PowerMonitorDelegate?

    private var runLoopSource: CFRunLoopSource?
    private var wasOnACPower = true
    private var isMonitoring = false

    // MARK: - Monitoring

    /// Start monitoring power state changes
    func startMonitoring() {
        guard !isMonitoring else { return }

        // Check initial state
        wasOnACPower = isOnACPower()

        // Create power source notification callback
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        runLoopSource = IOPSNotificationCreateRunLoopSource({ context in
            guard let context = context else { return }
            let monitor = Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue()
            monitor.handlePowerSourceChange()
        }, context).takeRetainedValue()

        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .defaultMode)
        isMonitoring = true

        print("[PowerMonitor] Started monitoring power state")
    }

    /// Stop monitoring power state changes
    func stopMonitoring() {
        guard isMonitoring else { return }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .defaultMode)
            runLoopSource = nil
        }

        isMonitoring = false
        print("[PowerMonitor] Stopped monitoring power state")
    }

    // MARK: - Power State

    /// Check if currently on AC power
    /// - Returns: true if on AC power, false if on battery
    func isOnACPower() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return true // Assume AC if unknown
        }

        for source in sources {
            if let info = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
               let powerSource = info[kIOPSPowerSourceStateKey as String] as? String {
                return powerSource == kIOPSACPowerValue as String
            }
        }

        return true
    }

    // MARK: - Private

    private func handlePowerSourceChange() {
        let isAC = isOnACPower()

        if wasOnACPower && !isAC {
            // Power cable disconnected
            print("[PowerMonitor] Power cable disconnected")
            DispatchQueue.main.async {
                self.delegate?.powerCableDisconnected()
            }
        } else if !wasOnACPower && isAC {
            // Power cable connected
            print("[PowerMonitor] Power cable connected")
            DispatchQueue.main.async {
                self.delegate?.powerCableConnected()
            }
        }

        wasOnACPower = isAC
    }

    deinit {
        stopMonitoring()
    }
}
