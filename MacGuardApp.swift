// MacGuardApp.swift
// MacGuard - Anti-Theft Alarm for macOS
// Created: 2025-12-18

import SwiftUI

/// App delegate to handle app lifecycle events
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        // Reset lid close protection on app exit to restore normal sleep behavior
        if AppSettings.shared.lidCloseProtection {
            AppSettings.shared.resetLidCloseProtection()
        }
    }
}

/// Main entry point for MacGuard menu bar application
@main
struct MacGuardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var alarmManager = AlarmStateManager()

    // Initialize update manager (starts Sparkle auto-update)
    private let updateManager = UpdateManager.shared

    init() {
        // Check for updates on app launch (silent - only shows UI if update available)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            UpdateManager.shared.checkForUpdatesInBackground()
        }
    }

    var body: some Scene {
        // Menu bar app (no main window)
        MenuBarExtra {
            MenuBarView()
                .environmentObject(alarmManager)
        } label: {
            MenuBarIconView(state: alarmManager.state)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Custom menu bar icon view with state-based color tint
struct MenuBarIconView: View {
    let state: AlarmState

    var body: some View {
        Image(systemName: iconName)
            .symbolRenderingMode(.palette)
            .foregroundStyle(iconColor)
    }

    private var iconName: String {
        switch state {
        case .idle:
            return "shield"
        case .armed:
            return "shield.fill"
        case .triggered, .alarming:
            return "exclamationmark.shield.fill"
        }
    }

    private var iconColor: Color {
        switch state {
        case .idle:
            return .primary
        case .armed:
            return .green
        case .triggered:
            return .orange
        case .alarming:
            return .red
        }
    }
}
