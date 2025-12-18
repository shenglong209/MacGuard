// MacGuardApp.swift
// MacGuard - Anti-Theft Alarm for macOS
// Created: 2025-12-18

import SwiftUI

/// Main entry point for MacGuard menu bar application
@main
struct MacGuardApp: App {
    @StateObject private var alarmManager = AlarmStateManager()

    var body: some Scene {
        // Menu bar app (no main window)
        MenuBarExtra {
            MenuBarView()
                .environmentObject(alarmManager)
        } label: {
            MenuBarIconView(state: alarmManager.state)
        }
        .menuBarExtraStyle(.menu)
    }
}

/// Custom menu bar icon view that uses custom image or SF Symbol based on state
struct MenuBarIconView: View {
    let state: AlarmState

    var body: some View {
        if state == .idle, let image = loadMenuBarIcon() {
            Image(nsImage: image)
        } else {
            // Use SF Symbols for armed/triggered/alarming states (more visible)
            Image(systemName: state.menuBarIcon)
        }
    }

    private func loadMenuBarIcon() -> NSImage? {
        guard let url = Bundle.module.url(forResource: "MenuBarIcon", withExtension: "png", subdirectory: "Resources"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        // Set as template for proper light/dark mode support
        image.isTemplate = true
        return image
    }
}
