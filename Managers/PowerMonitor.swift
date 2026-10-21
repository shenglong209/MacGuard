// PowerMonitor.swift
// MacGuard - Anti-Theft Alarm for macOS
// Created: 2025-12-18

import Foundation
import IOKit.ps

enum PowerSource: Equatable {
    case ac, battery
}

/// Monitors power cable connect/disconnect events
protocol PowerMonitorDelegate: AnyObject {
    func powerCableDisconnected()
}

class PowerMonitor {
    weak var delegate: PowerMonitorDelegate?

    private var session: (source: CFRunLoopSource, last: PowerSource)?

    // MARK: - Monitoring

    func startMonitoring() {
        guard session == nil else { return }

        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue().handlePowerSourceChange()
        }, context).takeRetainedValue()

        // Common modes: still delivered while a menu or modal is tracking
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        session = (source, Self.currentSource())

        logActivity(.power, "Started monitoring power state")
    }

    func stopMonitoring() {
        guard let session else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), session.source, .commonModes)
        self.session = nil
        logActivity(.power, "Stopped monitoring power state")
    }

    // MARK: - Power State

    /// The *providing* source: a UPS reports "AC Power" even after the laptop's cable is pulled.
    static func currentSource() -> PowerSource {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let providing = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() else {
            return .ac // Assume AC if unknown
        }
        return (providing as String) == kIOPSACPowerValue ? .ac : .battery
    }

    /// `nil` when nothing changed (IOKit also notifies on battery-level changes).
    static func transition(from previous: PowerSource, to current: PowerSource) -> PowerSource? {
        current == previous ? nil : current
    }

    // MARK: - Private

    private func handlePowerSourceChange() {
        guard let previous = session?.last,
              let source = Self.transition(from: previous, to: Self.currentSource()) else { return }
        session?.last = source

        logActivity(.power, source == .ac ? "Power cable connected" : "Power cable disconnected")
        if source == .battery { delegate?.powerCableDisconnected() }
    }

    deinit {
        stopMonitoring()
    }
}
