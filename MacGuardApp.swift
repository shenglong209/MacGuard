// MacGuardApp.swift
// MacGuard - Anti-Theft Alarm for macOS
// Created: 2025-12-18

import SwiftUI

/// Main entry point for MacGuard menu bar application
@main
struct MacGuardApp: App {
    @StateObject private var alarmManager = AlarmStateManager()

    // Initialize update manager (starts Sparkle auto-update)
    private let updateManager = UpdateManager.shared

    init() {
        // Check for updates on app launch (background, non-intrusive)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            UpdateManager.shared.checkForUpdates()
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

/// Custom menu bar icon view with state-based appearance
struct MenuBarIconView: View {
    let state: AlarmState

    var body: some View {
        HStack(spacing: 4) {
            if let image = loadMenuBarIcon() {
                Image(nsImage: image)
            } else {
                // Fallback to SF Symbol
                Image(systemName: "shield")
            }

            // Show colored dot indicator for active states
            if state != .idle {
                Circle()
                    .fill(indicatorColor)
                    .frame(width: 6, height: 6)
            }
        }
    }

    private func loadMenuBarIcon() -> NSImage? {
        guard let url = ResourceBundle.url(forResource: "MenuBarIcon", withExtension: "png", subdirectory: "Resources"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        // Template mode allows automatic light/dark mode adaptation
        image.isTemplate = true
        return image
    }

    private var indicatorColor: Color {
        switch state {
        case .idle:
            return .clear
        case .armed:
            return .green
        case .triggered:
            return .yellow
        case .alarming:
            return .red
        }
    }
}
