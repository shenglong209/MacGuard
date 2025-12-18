// SettingsWindowController.swift
// MacGuard - Anti-Theft Alarm for macOS
// Created: 2025-12-18

import SwiftUI
import AppKit

/// Singleton controller for the settings window
class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    private var hostingController: NSHostingController<SettingsView>?
    private weak var currentAlarmManager: AlarmStateManager?

    private override init() {
        super.init()
    }

    /// Show the settings window
    func show(alarmManager: AlarmStateManager) {
        print("[Settings] show() called")
        currentAlarmManager = alarmManager

        // Create window if needed
        if window == nil {
            createWindow(alarmManager: alarmManager)
        }

        // Temporarily become a regular app to take focus
        NSApp.setActivationPolicy(.regular)

        // Show and activate
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        print("[Settings] Window shown")
    }

    private func createWindow(alarmManager: AlarmStateManager) {
        print("[Settings] Creating window")

        let view = SettingsView(alarmManager: alarmManager)
        hostingController = NSHostingController(rootView: view)

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        newWindow.contentViewController = hostingController
        newWindow.title = "MacGuard Settings"
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self

        window = newWindow
        print("[Settings] Window created")
    }

    /// Hide the settings window
    func hide() {
        window?.orderOut(nil)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        print("[Settings] Window closed")
        // Revert to accessory app (menu bar only)
        NSApp.setActivationPolicy(.accessory)
    }
}
