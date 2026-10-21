// InputMonitor.swift
// MacGuard - Anti-Theft Alarm for macOS
// Created: 2025-12-18

import Cocoa
import ApplicationServices

/// User input that counts as an intrusion, parsed from raw `CGEventType`s at the boundary.
enum IntrusionInput: CaseIterable {
    case keyboard, mediaKey, modifier, click, drag, pointerMove, scroll

    /// NX_SYSDEFINED (media, volume, brightness keys); not a named `CGEventType`.
    private static let systemDefinedRawValue: UInt32 = 14

    /// The tap's event mask is derived from these, so mask and parser cannot disagree.
    var eventTypeRawValues: [UInt32] {
        switch self {
        case .keyboard: return [CGEventType.keyDown.rawValue]
        case .mediaKey: return [Self.systemDefinedRawValue]
        case .modifier: return [CGEventType.flagsChanged.rawValue]   // ⌘, ⌥, fn, ... alone
        case .click: return [CGEventType.leftMouseDown, .rightMouseDown, .otherMouseDown].map(\.rawValue)
        case .drag: return [CGEventType.leftMouseDragged, .rightMouseDragged, .otherMouseDragged].map(\.rawValue)
        case .pointerMove: return [CGEventType.mouseMoved.rawValue]
        case .scroll: return [CGEventType.scrollWheel.rawValue]
        }
    }

    init?(_ type: CGEventType) {
        guard let input = Self.allCases.first(where: { $0.eventTypeRawValues.contains(type.rawValue) }) else {
            return nil
        }
        self = input
    }

    var label: String {
        switch self {
        case .keyboard: return "keyboard"
        case .mediaKey: return "media/system key"
        case .modifier: return "modifier key"
        case .click: return "mouse click"
        case .drag: return "mouse drag"
        case .pointerMove: return "mouse move"
        case .scroll: return "scroll/touchpad"
        }
    }

    static let eventMask: CGEventMask = allCases
        .flatMap(\.eventTypeRawValues)
        .reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1) }
}

/// Monitors global keyboard, mouse, and touchpad input using CGEventTap
/// Requires Accessibility permission
protocol InputMonitorDelegate: AnyObject {
    func inputDetected(_ input: IntrusionInput)
}

class InputMonitor {
    weak var delegate: InputMonitorDelegate?

    private var tap: (port: CFMachPort, source: CFRunLoopSource)?

    // Debouncing to prevent event spam
    private var lastEventTime: Date = .distantPast
    private let debounceInterval: TimeInterval = 0.5


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

        guard tap == nil else { return true }

        // The tap's source runs on the main run loop, so callbacks arrive on main.
        dispatchPrecondition(condition: .onQueue(.main))

        let callback: CGEventTapCallBack = { _, type, event, refcon -> Unmanaged<CGEvent>? in
            if let refcon {
                Unmanaged<InputMonitor>.fromOpaque(refcon).takeUnretainedValue().handle(type)
            }
            // Listen-only: always pass the event through
            return Unmanaged.passUnretained(event)
        }

        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: IntrusionInput.eventMask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ), let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            logActivity(.input, "Failed to create event tap - check Accessibility permissions")
            return false
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tap = (port, source)

        logActivity(.input, "Started monitoring input events")
        return true
    }

    private func handle(_ type: CGEventType) {
        // The system disables a tap it considers slow; turn it back on
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap.port, enable: true) }
            return
        }
        guard let input = IntrusionInput(type) else { return }
        let now = Date()
        guard now.timeIntervalSince(lastEventTime) > debounceInterval else { return }
        lastEventTime = now
        delegate?.inputDetected(input)
    }

    /// Stop monitoring input events
    func stopMonitoring() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap.port, enable: false)
        // Drop the tap now: the callback holds an unretained pointer to self.
        CFMachPortInvalidate(tap.port)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), tap.source, .commonModes)
        self.tap = nil

        logActivity(.input, "Stopped monitoring input events")
    }

    deinit {
        stopMonitoring()
    }
}
