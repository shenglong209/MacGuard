// InputMonitor.swift
// MacGuard - Anti-Theft Alarm for macOS
// Created: 2025-12-18

import Cocoa
import ApplicationServices

/// Protocol for receiving input detection events
protocol InputMonitorDelegate: AnyObject {
    func inputDetected(eventType: CGEventType)
}

/// Monitors global keyboard, mouse, and touchpad input using CGEventTap
/// Requires Accessibility permission
class InputMonitor {
    weak var delegate: InputMonitorDelegate?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isMonitoring = false

    // Debouncing to prevent event spam
    private var lastEventTime: Date = .distantPast
    private let debounceInterval: TimeInterval = 0.5

    // MARK: - Logging Helper

    private func log(_ category: ActivityLogCategory, _ message: String) {
        Task { @MainActor in
            ActivityLogManager.shared.log(category, message)
        }
    }

    // Event types to monitor
    private static let eventMask: CGEventMask = {
        let types: [CGEventType] = [
            .keyDown,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,
            .mouseMoved,
            .scrollWheel
        ]
        return types.reduce(0) { $0 | (1 << $1.rawValue) }
    }()

    // MARK: - Permission Check

    /// Check if Accessibility permission is granted
    static func hasAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }

    /// Request Accessibility permission (shows system dialog)
    static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Monitoring

    /// Start monitoring input events
    /// - Returns: true if monitoring started successfully, false if permission denied
    func startMonitoring() -> Bool {
        guard Self.hasAccessibilityPermission() else {
            Self.requestAccessibilityPermission()
            return false
        }

        guard !isMonitoring else { return true }

        // Create event tap callback
        let callback: CGEventTapCallBack = { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
            // Handle tap disabled by system - re-enable via monitor's eventTap
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let refcon = refcon {
                    let monitor = Unmanaged<InputMonitor>.fromOpaque(refcon).takeUnretainedValue()
                    if let tap = monitor.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                }
                return Unmanaged.passUnretained(event)
            }

            // Notify delegate with debouncing
            if let refcon = refcon {
                let monitor = Unmanaged<InputMonitor>.fromOpaque(refcon).takeUnretainedValue()

                // Debounce check
                let now = Date()
                if now.timeIntervalSince(monitor.lastEventTime) > monitor.debounceInterval {
                    monitor.lastEventTime = now
                    DispatchQueue.main.async {
                        monitor.delegate?.inputDetected(eventType: type)
                    }
                }
            }

            // Pass event through (we're only listening, not blocking)
            return Unmanaged.passUnretained(event)
        }

        // Create event tap
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: Self.eventMask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            log(.input, "Failed to create event tap - check Accessibility permissions")
            return false
        }

        eventTap = tap

        // Add to run loop
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)

        // Enable tap
        CGEvent.tapEnable(tap: tap, enable: true)
        isMonitoring = true

        log(.input, "Started monitoring input events")
        return true
    }

    /// Stop monitoring input events
    func stopMonitoring() {
        guard isMonitoring else { return }

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
        isMonitoring = false

        log(.input, "Stopped monitoring input events")
    }

    deinit {
        stopMonitoring()
    }
}
