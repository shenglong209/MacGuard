// DeviceScannerView.swift
// MacGuard - Anti-Theft Alarm for macOS
// Created: 2025-12-18

import SwiftUI
import CoreBluetooth
import IOBluetooth

/// Window controller for device scanner
class DeviceScannerWindowController: NSObject, NSWindowDelegate {
    static let shared = DeviceScannerWindowController()

    private var window: NSWindow?
    private var hostingController: NSHostingController<DeviceScannerContainerView>?
    private var viewModel = DeviceScannerViewModel()

    private override init() {
        super.init()
    }

    func show(bluetoothManager: BluetoothProximityManager) {
        viewModel.bluetoothManager = bluetoothManager
        viewModel.discoveredDevices = []
        viewModel.isScanning = false

        if window == nil {
            createWindow()
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)

        // Start scanning
        viewModel.startScanning()
    }

    private func createWindow() {
        let view = DeviceScannerContainerView(viewModel: viewModel, onDismiss: { [weak self] in
            self?.viewModel.stopScanning()
            self?.window?.orderOut(nil)
            // Don't change activation policy - let Settings window handle it
        })
        hostingController = NSHostingController(rootView: view)

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 350, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        // Enable transparency for glass effects
        newWindow.isOpaque = false
        newWindow.backgroundColor = .clear

        newWindow.contentViewController = hostingController
        newWindow.title = "Scan for Devices"
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self

        window = newWindow
    }

    func windowWillClose(_ notification: Notification) {
        viewModel.stopScanning()
        // Don't change activation policy - let Settings window handle it
    }
}

/// View model for device scanner
class DeviceScannerViewModel: NSObject, ObservableObject {
    var bluetoothManager: BluetoothProximityManager?
    @Published var discoveredDevices: [DiscoveredDevice] = []
    @Published var isScanning = false

    private var centralManager: CBCentralManager?
    private var bleDeviceUUIDs: Set<UUID> = []  // Track which devices were found via BLE

    func startScanning() {
        guard !isScanning else { return }
        isScanning = true
        discoveredDevices = []
        bleDeviceUUIDs = []

        // First, load all paired devices from IOBluetooth (Classic + BLE)
        loadPairedDevices()

        // Then start BLE scan to get RSSI and detect BLE-capable devices
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    /// Load all paired devices from IOBluetooth
    private func loadPairedDevices() {
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return
        }

        for ioDevice in paired {
            guard let name = ioDevice.name, !name.isEmpty else { continue }

            // Create discovered device with IOBluetooth data
            let device = DiscoveredDevice(
                id: UUID(),  // Generate new UUID (will be replaced if found via BLE)
                name: name,
                rssi: ioDevice.isConnected() ? Int(ioDevice.rawRSSI()) : -80,
                isPaired: true,
                bluetoothAddress: ioDevice.addressString,
                isClassicBluetooth: true,  // Assume classic until proven BLE
                isConnected: ioDevice.isConnected()
            )

            discoveredDevices.append(device)
            print("[Scanner] Paired device: \(name) (addr: \(ioDevice.addressString ?? "?"), connected: \(ioDevice.isConnected()))")
        }

        // Sort by connection status, then by signal strength
        sortDevices()
    }

    func stopScanning() {
        centralManager?.stopScan()
        centralManager = nil
        isScanning = false
    }

    func selectDevice(_ device: DiscoveredDevice) {
        guard let bluetoothManager = bluetoothManager else { return }

        // Create a TrustedDevice with appropriate type
        let trustedDevice = TrustedDevice(
            id: device.id,
            name: device.name,
            bluetoothAddress: device.bluetoothAddress,
            isClassicBluetooth: device.isClassicBluetooth
        )

        // Add device via BluetoothProximityManager
        let added = bluetoothManager.addTrustedDevice(trustedDevice)
        if added {
            print("[Scanner] Added device: \(device.name) (classic: \(device.isClassicBluetooth))")
        }
    }

    /// Check if device is already trusted
    func isDeviceAlreadyTrusted(_ device: DiscoveredDevice) -> Bool {
        guard let manager = bluetoothManager else { return false }

        // Check by ID or Bluetooth address
        return manager.trustedDevices.contains {
            $0.id == device.id ||
            (device.bluetoothAddress != nil && $0.bluetoothAddress == device.bluetoothAddress)
        }
    }

    /// Check if max devices reached
    var isMaxDevicesReached: Bool {
        (bluetoothManager?.trustedDevices.count ?? 0) >= 10
    }

    private func sortDevices() {
        discoveredDevices.sort { a, b in
            // Connected devices first
            if a.isConnected != b.isConnected {
                return a.isConnected
            }
            // Then by signal strength
            return a.rssi > b.rssi
        }
    }
}

extension DeviceScannerViewModel: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            // Scan for BLE peripherals to identify BLE-capable devices
            central.scanForPeripherals(
                withServices: nil,
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
            )
            print("[Scanner] Started BLE scanning to identify device types")
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard let name = peripheral.name, !name.isEmpty else { return }
        guard RSSI.intValue > -90 else { return }

        // Find matching device in our paired list by name
        // Only update existing paired devices - ignore unpaired BLE devices
        if let index = discoveredDevices.firstIndex(where: {
            $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }) {
            var device = discoveredDevices[index]

            // Device found via BLE scan - it supports BLE RSSI tracking
            // Update to use BLE (even if it was initially loaded from IOBluetooth)
            device.id = peripheral.identifier
            device.rssi = RSSI.intValue
            device.isClassicBluetooth = false  // Supports BLE
            discoveredDevices[index] = device
            bleDeviceUUIDs.insert(peripheral.identifier)
            print("[Scanner] Device \(name) found via BLE, UUID: \(peripheral.identifier)")
        }
        // Note: Unpaired BLE devices are intentionally ignored - only paired devices shown

        DispatchQueue.main.async {
            self.sortDevices()
        }
    }
}

/// Discovered device model
struct DiscoveredDevice: Identifiable {
    var id: UUID
    let name: String
    var rssi: Int
    let isPaired: Bool
    let bluetoothAddress: String?
    var isClassicBluetooth: Bool
    var isConnected: Bool
}

/// Container view with glass styling
struct DeviceScannerContainerView: View {
    @ObservedObject var viewModel: DeviceScannerViewModel
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header with glass background
            HStack(spacing: Theme.Spacing.md) {
                if viewModel.isScanning {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Scanning for paired devices...")
                        .font(.body)
                        .foregroundStyle(.secondary)
                } else {
                    ZStack {
                        GlassIconCircle(size: 28, material: .selection)
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.Accent.primary)
                    }
                    Text("Select a paired device")
                        .font(.body.weight(.medium))
                }
                Spacer()
            }
            .padding(Theme.Spacing.lg)
            .background {
                GlassBackground(material: .headerView, cornerRadius: 0)
            }

            // Device list
            if viewModel.discoveredDevices.isEmpty {
                emptyStateView
            } else {
                deviceListView
            }

            // Footer with glass background
            HStack {
                Button {
                    onDismiss()
                } label: {
                    Text("Cancel")
                        .frame(width: 70)
                }
                .buttonStyle(GlassSecondaryButtonStyle())

                Spacer()

                Button {
                    if viewModel.isScanning {
                        viewModel.stopScanning()
                    } else {
                        viewModel.startScanning()
                    }
                } label: {
                    Label(
                        viewModel.isScanning ? "Stop" : "Rescan",
                        systemImage: viewModel.isScanning ? "stop.fill" : "arrow.clockwise"
                    )
                }
                .buttonStyle(GlassBorderedProminentButtonStyle(tint: Theme.Accent.primary))
            }
            .padding(Theme.Spacing.lg)
            .background {
                GlassBackground(material: .headerView, cornerRadius: 0)
            }
        }
        .frame(width: 350, height: 400)
        .background {
            VisualEffectView(
                material: .sidebar,
                blendingMode: .behindWindow,
                isEmphasized: true
            )
            .ignoresSafeArea()
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()

            ZStack {
                GlassIconCircle(size: 100, material: .selection)
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 40))
                    .foregroundStyle(Theme.Accent.primary)
            }

            VStack(spacing: Theme.Spacing.sm) {
                Text("Looking for paired devices...")
                    .font(.system(.headline, design: .rounded))
                Text("Pair your device in System Settings → Bluetooth first")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()
        }
    }

    // MARK: - Device List

    private var deviceListView: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Spacing.sm) {
                ForEach(viewModel.discoveredDevices) { device in
                    let isAlreadyAdded = viewModel.isDeviceAlreadyTrusted(device)
                    DeviceRowButton(
                        device: device,
                        isAlreadyAdded: isAlreadyAdded,
                        isDisabled: isAlreadyAdded || viewModel.isMaxDevicesReached
                    ) {
                        viewModel.selectDevice(device)
                        onDismiss()
                    }
                }
            }
            .padding(Theme.Spacing.md)
        }
    }

}

// MARK: - Device Row Button

struct DeviceRowButton: View {
    let device: DiscoveredDevice
    var isAlreadyAdded: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.md) {
                // Device icon with glass background
                ZStack {
                    GlassIconCircle(size: 40, material: .selection)
                    Image(systemName: TrustedDevice.icon(for: device.name))
                        .font(.system(size: 18))
                        .foregroundStyle(isAlreadyAdded ? .secondary : Theme.Accent.primary)
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Text(device.name)
                            .font(.body.weight(.medium))
                            .foregroundStyle(isAlreadyAdded ? .secondary : .primary)

                        // Added badge for already-added devices
                        if isAlreadyAdded {
                            Text("Added")
                                .font(.caption2)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.StateColor.armed)
                                .clipShape(Capsule())
                        } else if device.isConnected {
                            // Connected badge
                            Text("Connected")
                                .font(.caption2)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.StateColor.armed)
                                .clipShape(Capsule())
                        } else if device.isPaired {
                            // Paired badge
                            Text("Paired")
                                .font(.caption2)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange)
                                .clipShape(Capsule())
                        }
                    }

                    // Device type and signal info
                    HStack(spacing: Theme.Spacing.xs) {
                        if device.isConnected {
                            SignalStrengthView(rssi: device.rssi)
                            Text(signalStrengthText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Image(systemName: device.isClassicBluetooth ? "antenna.radiowaves.left.and.right" : "wave.3.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(device.isClassicBluetooth ? "Classic BT" : "BLE")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                if !isAlreadyAdded {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
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
                        .opacity(isHovered && !isDisabled ? 1 : 0)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
            }
            .glassBorder(cornerRadius: Theme.CornerRadius.md)
            .opacity(isDisabled ? 0.6 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: Theme.Animation.hoverDuration)) {
                isHovered = hovering
            }
        }
    }

    private var signalStrengthText: String {
        if device.rssi >= -50 { return "Excellent" }
        if device.rssi >= -60 { return "Good" }
        if device.rssi >= -70 { return "Fair" }
        return "Weak"
    }
}

/// Visual signal strength indicator
struct SignalStrengthView: View {
    let rssi: Int

    private var bars: Int {
        if rssi >= -50 { return 4 }
        if rssi >= -60 { return 3 }
        if rssi >= -70 { return 2 }
        return 1
    }

    private var color: Color {
        switch bars {
        case 4: return .green
        case 3: return .green
        case 2: return .yellow
        default: return .orange
        }
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(index < bars ? color : Color.gray.opacity(0.3))
                    .frame(width: 3, height: CGFloat(4 + index * 2))
            }
        }
    }
}
