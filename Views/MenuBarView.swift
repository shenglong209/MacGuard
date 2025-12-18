// MenuBarView.swift
// MacGuard - Anti-Theft Alarm for macOS
// Created: 2025-12-18

import SwiftUI

/// Menu bar dropdown content view
struct MenuBarView: View {
    @EnvironmentObject var alarmManager: AlarmStateManager

    var body: some View {
        Group {
            // Permission warning (when Accessibility not granted)
            if !alarmManager.hasAccessibilityPermission {
                accessibilityWarning
                Divider()
            }

            // State-specific content
            stateContent

            Divider()

            // Trusted device status
            if let device = alarmManager.bluetoothManager.trustedDevice {
                HStack {
                    Image(systemName: device.isNearby ? "iphone.circle.fill" : "iphone.circle")
                        .foregroundColor(device.isNearby ? .green : .secondary)
                    Text(device.name)
                        .foregroundColor(device.isNearby ? .green : .secondary)
                }
                Divider()
            }

            // Settings
            Button("Settings...") {
                // Dispatch async to ensure menu closes first
                DispatchQueue.main.async {
                    SettingsWindowController.shared.show(alarmManager: alarmManager)
                }
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            // Quit
            Button("Quit MacGuard") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var accessibilityWarning: some View {
        Text("⚠️ Accessibility Required")
            .foregroundColor(.orange)
        Button("Grant Permission...") {
            alarmManager.requestAccessibilityPermission()
        }
    }

    @ViewBuilder
    private var stateContent: some View {
        switch alarmManager.state {
        case .idle:
            idleContent
        case .armed:
            armedContent
        case .triggered:
            triggeredContent
        case .alarming:
            alarmingContent
        }
    }

    private var idleContent: some View {
        Button("Arm MacGuard") {
            alarmManager.arm()
        }
    }

    @ViewBuilder
    private var armedContent: some View {
        HStack {
            Image(systemName: "checkmark.shield.fill")
                .foregroundColor(.green)
            Text("Armed")
                .foregroundColor(.green)
        }

        Button("Disarm") {
            alarmManager.disarm()
        }
    }

    @ViewBuilder
    private var triggeredContent: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)
            Text("Countdown: \(alarmManager.countdownSeconds)s")
                .foregroundColor(.yellow)
        }

        Button("Disarm (Touch ID)") {
            alarmManager.attemptBiometricDisarm { _ in }
        }
    }

    @ViewBuilder
    private var alarmingContent: some View {
        HStack {
            Image(systemName: "bell.badge.fill")
                .foregroundColor(.red)
            Text("ALARM ACTIVE")
                .foregroundColor(.red)
                .fontWeight(.bold)
        }

        Button("Stop Alarm (Auth Required)") {
            alarmManager.attemptBiometricDisarm { _ in }
        }
    }
}

#Preview {
    MenuBarView()
        .environmentObject(AlarmStateManager())
        .frame(width: 200)
}
