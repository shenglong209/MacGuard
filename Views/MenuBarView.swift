// MenuBarView.swift
// MacGuard - Anti-Theft Alarm for macOS
// Created: 2025-12-18

import SwiftUI

/// Custom button style with hover effect for menu items
struct MenuItemButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovered = hovering
            }
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isPressed {
            return Color.accentColor.opacity(0.2)
        } else if isHovered {
            return Color.primary.opacity(0.08)
        } else {
            return Color.clear
        }
    }
}

/// Menu bar dropdown content view (window style)
struct MenuBarView: View {
    @EnvironmentObject var alarmManager: AlarmStateManager

    var body: some View {
        VStack(spacing: 0) {
            // Permission warning
            if !alarmManager.hasAccessibilityPermission {
                accessibilityWarning
                Divider().padding(.vertical, 8)
            }

            // State section
            stateSection

            Divider().padding(.vertical, 10)

            // Trusted device section
            if let device = alarmManager.bluetoothManager.trustedDevice {
                deviceSection(device)
                Divider().padding(.vertical, 10)
            }

            // Actions
            actionsSection
        }
        .padding(14)
        .frame(width: 240)
    }

    // MARK: - Sections

    @ViewBuilder
    private var accessibilityWarning: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Accessibility Required")
                .font(.subheadline.weight(.medium))
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        Button {
            alarmManager.requestAccessibilityPermission()
        } label: {
            Text("Grant Permission...")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .padding(.top, 4)
    }

    @ViewBuilder
    private var stateSection: some View {
        switch alarmManager.state {
        case .idle:
            idleView
        case .armed:
            armedView
        case .triggered:
            triggeredView
        case .alarming:
            alarmingView
        }
    }

    private func deviceSection(_ device: TrustedDevice) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(device.isNearby ? Color.green.opacity(0.15) : Color.secondary.opacity(0.1))
                    .frame(width: 32, height: 32)
                Image(systemName: device.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(device.isNearby ? .green : .secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.subheadline.weight(.medium))
                Text(device.isNearby ? "Nearby" : "Not detected")
                    .font(.caption)
                    .foregroundStyle(device.isNearby ? .green : .secondary)
            }

            Spacer()

            if device.isNearby {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
            }
        }
    }

    private var actionsSection: some View {
        VStack(spacing: 4) {
            Button {
                SettingsWindowController.shared.show(alarmManager: alarmManager)
            } label: {
                HStack {
                    Image(systemName: "gearshape")
                    Text("Settings")
                    Spacer()
                    Text("⌘,")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(MenuItemButtonStyle())

            Button {
                UpdateManager.shared.checkForUpdates()
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.down")
                    Text("Check for Updates")
                    Spacer()
                }
            }
            .buttonStyle(MenuItemButtonStyle())
            .disabled(!UpdateManager.shared.canCheckForUpdates)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                HStack {
                    Image(systemName: "power")
                    Text("Quit")
                    Spacer()
                    Text("⌘Q")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(MenuItemButtonStyle())
        }
    }

    // MARK: - State Views

    private var idleView: some View {
        Button {
            alarmManager.arm()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "shield.fill")
                Text("Arm MacGuard")
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private var armedView: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                Text("Protected")
                    .font(.headline)
                    .foregroundStyle(.green)
                Spacer()
                Circle()
                    .fill(.green)
                    .frame(width: 10, height: 10)
            }

            Button {
                alarmManager.disarm()
            } label: {
                HStack {
                    Image(systemName: "lock.open")
                    Text("Disarm")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
    }

    private var triggeredView: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Intrusion Detected")
                        .font(.headline)
                        .foregroundStyle(.orange)
                    Text("\(alarmManager.countdownSeconds)s until alarm")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Button {
                alarmManager.attemptBiometricDisarm { _ in }
            } label: {
                HStack {
                    Image(systemName: "touchid")
                    Text("Disarm with Touch ID")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .controlSize(.regular)
        }
    }

    private var alarmingView: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "bell.badge.waveform.fill")
                    .font(.title2)
                    .foregroundStyle(.red)
                Text("ALARM ACTIVE")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.red)
                Spacer()
            }

            Button {
                alarmManager.attemptBiometricDisarm { _ in }
            } label: {
                HStack {
                    Image(systemName: "hand.raised.fill")
                    Text("Stop Alarm")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.regular)
        }
    }

}

#Preview {
    MenuBarView()
        .environmentObject(AlarmStateManager())
}
