// SettingsWindowController.swift
// MacGuard - Anti-Theft Alarm for macOS
// Created: 2025-12-18

import SwiftUI
import AppKit

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: UtilityWindow?

    func show(alarmManager: AlarmStateManager) {
        window = window ?? UtilityWindow(
            title: "MacGuard Settings", size: NSSize(width: 420, height: 520),
            style: [.titled, .closable, .miniaturizable], transparent: true,
            content: SettingsView(alarmManager: alarmManager))
        window?.show()
        logActivity(.system, "Settings window shown")
    }
}
