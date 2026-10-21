// MacGuardApp.swift
// MacGuard - Anti-Theft Alarm for macOS
// Created: 2025-12-18

import SwiftUI

/// App delegate to handle app lifecycle events
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    /// Owned here (not by the SwiftUI scene) so termination can consult it.
    let alarmManager = AlarmStateManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Login, a manual launch and the watchdog can all start MacGuard; the first wins.
        if let other = Self.otherRunningInstance() {
            other.activate()
            exit(0)
        }

        let tamperGuard = TamperGuard.shared
        if case .resumeAfterTamper(let session) = tamperGuard.launchDecision() {
            alarmManager.resumeAfterTamper(session)
        }
        tamperGuard.syncAgent()
    }

    /// Reopening shows Settings, so the app is reachable when the menu bar icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindowController.shared.show(alarmManager: alarmManager)
        return false
    }

    private static func otherRunningInstance() -> NSRunningApplication? {
        guard let bundleID = Bundle.main.bundleIdentifier else { return nil }
        let me = ProcessInfo.processInfo.processIdentifier
        // The headless watchdog shares the bundle id; its activation policy excludes it.
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first { $0.processIdentifier != me && $0.activationPolicy != .prohibited }
    }

    /// With the overlay up the app has a menu, so ⌘Q would otherwise silence the alarm.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard alarmManager.state == .idle else {
            ActivityLogManager.shared.log(.system, "Quit blocked - disarm first")
            return .terminateCancel
        }
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Reset lid close protection on app exit to restore normal sleep behavior
        AppSettings.shared.resetLidCloseProtection()
        ActivityLogManager.shared.flush()
    }
}

/// MacGuard menu bar application (started from main.swift)
struct MacGuardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

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
                .environmentObject(appDelegate.alarmManager)
        } label: {
            MenuBarIconView(alarmManager: appDelegate.alarmManager)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Custom menu bar icon view with state-based color tint
struct MenuBarIconView: View {
    @ObservedObject var alarmManager: AlarmStateManager

    var body: some View {
        Image(systemName: iconName)
            .symbolRenderingMode(.palette)
            .foregroundStyle(iconColor)
    }

    private var iconName: String {
        switch alarmManager.state.phase {
        case .idle:
            return "shield"
        case .arming, .armed:
            return "shield.fill"
        case .triggered, .alarming:
            return "exclamationmark.shield.fill"
        }
    }

    private var iconColor: Color {
        switch alarmManager.state.phase {
        case .idle:
            return .primary
        case .arming:
            return .secondary
        case .armed:
            return .green
        case .triggered:
            return .orange
        case .alarming:
            return .red
        }
    }
}
