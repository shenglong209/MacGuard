// TrustedDevicesConfigView.swift
// MacGuard - Anti-Theft Alarm for macOS
// Created: 2025-12-24

import SwiftUI

/// Window controller for trusted devices configuration
class TrustedDevicesConfigWindowController: NSObject, NSWindowDelegate {
    static let shared = TrustedDevicesConfigWindowController()

    private var window: NSWindow?
    private var hostingController: NSHostingController<TrustedDevicesConfigContainerView>?
    private var bluetoothManager: BluetoothProximityManager?

    private override init() {
        super.init()
    }

    func show(bluetoothManager: BluetoothProximityManager) {
        self.bluetoothManager = bluetoothManager

        if window == nil {
            createWindow()
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    private func createWindow() {
        guard let bluetoothManager = bluetoothManager else { return }

        let view = TrustedDevicesConfigContainerView(
            bluetoothManager: bluetoothManager,
            onDismiss: { [weak self] in
                self?.window?.orderOut(nil)
            }
        )
        hostingController = NSHostingController(rootView: view)

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        newWindow.isOpaque = false
        newWindow.backgroundColor = .clear
        newWindow.contentViewController = hostingController
        newWindow.title = "Trusted Devices"
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self

        window = newWindow
    }

    func windowWillClose(_ notification: Notification) {
        // Don't change activation policy - let Settings window handle it
    }
}

/// Container view for trusted devices configuration
struct TrustedDevicesConfigContainerView: View {
    @ObservedObject var bluetoothManager: BluetoothProximityManager
    @ObservedObject private var settings = AppSettings.shared
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Device list
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    if bluetoothManager.trustedDevices.isEmpty {
                        emptyStateView
                    } else {
                        deviceListView
                    }
                }
                .padding(Theme.Spacing.lg)
            }

            Divider()

            // Settings section
            if !bluetoothManager.trustedDevices.isEmpty {
                settingsSection
                Divider()
            }

            // Footer
            footerView
        }
        .frame(width: 450, height: 500)
        .background {
            VisualEffectView(
                material: .sidebar,
                blendingMode: .behindWindow,
                isEmphasized: true
            )
            .ignoresSafeArea()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: Theme.Spacing.md) {
            ZStack {
                GlassIconCircle(size: 36, material: .selection)
                Image(systemName: "iphone")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.Accent.primary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Trusted Devices")
                    .font(.headline)
                Text("\(bluetoothManager.trustedDevices.count) of 10 devices")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(Theme.Spacing.lg)
        .background {
            GlassBackground(material: .headerView, cornerRadius: 0)
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()

            ZStack {
                GlassIconCircle(size: 80, material: .selection)
                Image(systemName: "iphone.slash")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: Theme.Spacing.sm) {
                Text("No Trusted Devices")
                    .font(.headline)
                Text("Add a paired Bluetooth device to enable proximity-based auto-arm and auto-disarm.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                DeviceScannerWindowController.shared.show(bluetoothManager: bluetoothManager)
            } label: {
                Label("Add Device", systemImage: "plus.circle")
            }
            .buttonStyle(GlassBorderedProminentButtonStyle(tint: Theme.Accent.primary))

            Spacer()
        }
        .padding(Theme.Spacing.xl)
    }

    // MARK: - Device List

    private var deviceListView: some View {
        VStack(spacing: Theme.Spacing.sm) {
            ForEach(bluetoothManager.trustedDevices) { device in
                deviceRow(device)
            }
        }
    }

    private func deviceRow(_ device: TrustedDevice) -> some View {
        let connectionStatus = bluetoothManager.connectionStatus(for: device)
        let isNearby = device.lastRSSI.map { $0 >= AppSettings.shared.proximityDistance.awayThreshold } ?? false

        return HStack(spacing: Theme.Spacing.md) {
            // Device icon
            ZStack {
                GlassIconCircle(size: 40, material: .selection)
                Image(systemName: device.icon)
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.Accent.primary)
            }

            // Device info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.Spacing.sm) {
                    Text(device.name)
                        .font(.body.weight(.medium))

                    // Type badge
                    Text(device.isClassicBluetooth ? "Classic" : "BLE")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(device.isClassicBluetooth ? Color.orange : Color.blue)
                        .clipShape(Capsule())
                }

                HStack(spacing: Theme.Spacing.sm) {
                    // Connection status
                    Label(connectionStatus.label, systemImage: connectionStatus.icon)
                        .font(.caption)
                        .foregroundColor(connectionStatus == .connected ? Theme.StateColor.armed : .secondary)

                    if let rssi = device.lastRSSI {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text("\(rssi) dBm")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // Nearby indicator
            if isNearby {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(Theme.StateColor.armed)
            }

            // Remove button
            Button {
                bluetoothManager.removeTrustedDevice(device)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove device")
        }
        .padding(Theme.Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                .fill(.clear)
                .background(
                    VisualEffectView(
                        material: .selection,
                        blendingMode: .withinWindow
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
        }
        .glassBorder(cornerRadius: Theme.CornerRadius.md)
    }

    // MARK: - Settings Section

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            // Detection Distance
            HStack {
                Text("Detection Distance")
                Spacer()
                Picker("", selection: $settings.proximityDistance) {
                    ForEach(ProximityDistance.allCases) { distance in
                        Text("\(distance.rawValue) (\(distance.description))").tag(distance)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 180)
            }

            // Auto-arm toggle
            Toggle("Auto-arm when devices leave", isOn: $settings.autoArmOnDeviceLeave)

            if settings.autoArmOnDeviceLeave {
                // Mode picker (only when multiple devices)
                if bluetoothManager.trustedDevices.count > 1 {
                    HStack {
                        Text("Trigger when")
                        Spacer()
                        Picker("", selection: $settings.autoArmMode) {
                            ForEach(AutoArmMode.allCases) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 150)
                    }
                }

                // Grace period
                HStack {
                    Text("Grace period")
                    Spacer()
                    Picker("", selection: $settings.autoArmGracePeriod) {
                        Text("10 sec").tag(10)
                        Text("15 sec").tag(15)
                        Text("30 sec").tag(30)
                        Text("60 sec").tag(60)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 100)
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .background {
            GlassBackground(material: .headerView, cornerRadius: 0)
        }
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            Button {
                onDismiss()
            } label: {
                Text("Done")
                    .frame(width: 70)
            }
            .buttonStyle(GlassSecondaryButtonStyle())

            Spacer()

            Button {
                DeviceScannerWindowController.shared.show(bluetoothManager: bluetoothManager)
            } label: {
                Label("Add Device", systemImage: "plus.circle")
            }
            .buttonStyle(GlassBorderedProminentButtonStyle(tint: Theme.Accent.primary))
            .disabled(bluetoothManager.trustedDevices.count >= 10)
        }
        .padding(Theme.Spacing.lg)
        .background {
            GlassBackground(material: .headerView, cornerRadius: 0)
        }
    }
}
