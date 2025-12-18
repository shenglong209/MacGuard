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
            Image(systemName: alarmManager.state.menuBarIcon)
        }
        .menuBarExtraStyle(.menu)
    }
}
