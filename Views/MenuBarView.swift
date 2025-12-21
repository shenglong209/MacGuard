// MenuBarView.swift
// MacGuard - Anti-Theft Alarm for macOS
// Created: 2025-12-18

import SwiftUI

/// Menu bar dropdown content view (window style)
struct MenuBarView: View {
    @EnvironmentObject var alarmManager: AlarmStateManager

    var body: some View {
        VStack(spacing: 0) {
            // Permission warning
            if !alarmManager.hasAccessibilityPermission {
                accessibilityWarning
                Divider()
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.sm)
            }

            // State section
            stateSection

            Divider()
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.md)

            // Trusted device section
            if let device = alarmManager.bluetoothManager.trustedDevice {
                deviceSection(device)
                Divider()
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.md)
            }

            // Actions
            actionsSection
        }
        .padding(Theme.Spacing.lg)
        .frame(width: 240)
        .background {
            GlassBackground(material: .menu, cornerRadius: Theme.CornerRadius.md + 2)
                .dropdownShadow()
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var accessibilityWarning: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.StateColor.triggered)
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
        .buttonStyle(GlassBorderedProminentButtonStyle(tint: Theme.StateColor.triggered))
        .padding(.top, Theme.Spacing.xs)
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
        let isNearby = alarmManager.bluetoothManager.isDeviceNearby
        return HStack(spacing: Theme.Spacing.md) {
            ZStack {
                GlassIconCircle(size: 32, material: .selection)
                Image(systemName: device.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(isNearby ? Theme.StateColor.armed : .secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.subheadline.weight(.medium))
                Text(isNearby ? "Nearby" : "Not detected")
                    .font(.caption)
                    .foregroundStyle(isNearby ? Theme.StateColor.armed : .secondary)
            }

            Spacer()

            if isNearby {
                Circle()
                    .fill(Theme.StateColor.armed)
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle()
                            .strokeBorder(Theme.StateColor.armed.opacity(0.3), lineWidth: 1)
                    )
            }
        }
    }

    private var actionsSection: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Button {
                SettingsWindowController.shared.show(alarmManager: alarmManager)
            } label: {
                HStack {
                    Image(systemName: "gearshape")
                        .foregroundStyle(.secondary)
                    Text("Settings")
                    Spacer()
                    Text("⌘,")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(GlassMenuRowButtonStyle())

            Button {
                UpdateManager.shared.checkForUpdates()
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.down")
                        .foregroundStyle(.secondary)
                    Text("Check for Updates")
                    Spacer()
                }
            }
            .buttonStyle(GlassMenuRowButtonStyle())
            .disabled(!UpdateManager.shared.canCheckForUpdates)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                HStack {
                    Image(systemName: "power")
                        .foregroundStyle(.secondary)
                    Text("Quit")
                    Spacer()
                    Text("⌘Q")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(GlassMenuRowButtonStyle())
        }
    }

    // MARK: - State Views

    private var idleView: some View {
        Button {
            alarmManager.arm()
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "shield.fill")
                Text("Arm MacGuard")
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(GlassBorderedProminentButtonStyle(tint: Theme.Accent.primary))
    }

    private var armedView: some View {
        VStack(spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.StateColor.armed)
                Text("Protected")
                    .font(.headline)
                    .foregroundStyle(Theme.StateColor.armed)
                Spacer()
                Circle()
                    .fill(Theme.StateColor.armed)
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle()
                            .strokeBorder(Theme.StateColor.armed.opacity(0.3), lineWidth: 1)
                    )
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
            .buttonStyle(GlassSecondaryButtonStyle())
        }
    }

    private var triggeredView: some View {
        VStack(spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.StateColor.triggered)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Intrusion Detected")
                        .font(.headline)
                        .foregroundStyle(Theme.StateColor.triggered)
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
            .buttonStyle(GlassBorderedProminentButtonStyle(tint: Theme.StateColor.triggered))
        }
    }

    private var alarmingView: some View {
        VStack(spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "bell.badge.waveform.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.StateColor.alarming)
                Text("ALARM ACTIVE")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Theme.StateColor.alarming)
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
            .buttonStyle(GlassBorderedProminentButtonStyle(tint: Theme.StateColor.alarming))
        }
    }
}

#Preview {
    MenuBarView()
        .environmentObject(AlarmStateManager())
}
