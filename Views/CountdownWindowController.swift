// CountdownWindowController.swift
// MacGuard - Anti-Theft Alarm for macOS
// Created: 2025-12-18

import SwiftUI
import AppKit

/// Custom window that can become key even when borderless
class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// The fullscreen overlay, kept and reshown (closing it crashed during cleanup).
@MainActor
final class CountdownWindowController {
    private let window: KeyableWindow

    init(alarmManager: AlarmStateManager) {
        window = KeyableWindow(contentRect: NSScreen.main?.frame ?? .zero, styleMask: [.borderless],
                               backing: .buffered, defer: false)
        window.contentViewController = NSHostingController(rootView: CountdownOverlayView(alarmManager: alarmManager))
        window.level = .screenSaver
        window.backgroundColor = NSColor.black.withAlphaComponent(0.85)
        window.isOpaque = false
        window.acceptsMouseMovedEvents = true
    }

    func show() {
        if let screen = NSScreen.main {
            window.setFrame(screen.frame, display: true)
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        logActivity(.system, "Countdown overlay shown")
    }

    func hide() {
        window.orderOut(nil)
        logActivity(.system, "Countdown overlay hidden")
    }
}
