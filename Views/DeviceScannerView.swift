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
    private var pairedDeviceNames: Set<String> = []

    func startScanning() {
        guard !isScanning else { return }
        isScanning = true
        discoveredDevices = []

        // Get paired device names from IOBluetooth
        loadPairedDeviceNames()

        // Create central manager for BLE discovery (to get RSSI)
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    /// Load paired device names from system Bluetooth
    private func loadPairedDeviceNames() {
        pairedDeviceNames = []
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return
        }
        for device in paired {
            if let name = device.name, !name.isEmpty {
                pairedDeviceNames.insert(name)
                print("[Scanner] Paired device: \(name)")
            }
        }
    }

    func stopScanning() {
        centralManager?.stopScan()
        centralManager = nil
        isScanning = false
    }

    func selectDevice(_ device: DiscoveredDevice) {
        guard let bluetoothManager = bluetoothManager else { return }

        // Create a TrustedDevice and save it
        let trustedDevice = TrustedDevice(
            id: device.id,
            name: device.name
        )

        // Save directly via UserDefaults
        if let data = try? JSONEncoder().encode(trustedDevice) {
            UserDefaults.standard.set(data, forKey: "MacGuard.trustedDevice")
        }

        // Reload in bluetooth manager
        bluetoothManager.reloadTrustedDevice()

        print("[Scanner] Selected device: \(device.name)")
    }
}

extension DeviceScannerViewModel: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            // Scan for peripherals to get RSSI readings
            central.scanForPeripherals(
                withServices: nil,
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
            )
            print("[Scanner] Started scanning for paired devices")
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard let name = peripheral.name, !name.isEmpty else { return }

        // Only show devices that are paired (match by name)
        guard pairedDeviceNames.contains(name) else { return }

        // Check if already in list
        if !discoveredDevices.contains(where: { $0.id == peripheral.identifier }) {
            let device = DiscoveredDevice(
                id: peripheral.identifier,
                name: name,
                rssi: RSSI.intValue
            )
            DispatchQueue.main.async {
                self.discoveredDevices.append(device)
                self.discoveredDevices.sort { $0.rssi > $1.rssi }
            }
            print("[Scanner] Found paired device: \(name) (RSSI: \(RSSI))")
        }
    }
}

/// Discovered device model
struct DiscoveredDevice: Identifiable {
    let id: UUID
    let name: String
    let rssi: Int
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
                Text("Only devices paired with this Mac will appear")
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
                    DeviceRowButton(device: device) {
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
                        .foregroundStyle(Theme.Accent.primary)
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(device.name)
                        .font(.body.weight(.medium))

                    // Signal strength indicator
                    HStack(spacing: Theme.Spacing.xs) {
                        SignalStrengthView(rssi: device.rssi)
                        Text(signalStrengthText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
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
                        .opacity(isHovered ? 1 : 0)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
            }
            .glassBorder(cornerRadius: Theme.CornerRadius.md)
        }
        .buttonStyle(.plain)
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
