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
    private weak var parentWindow: NSWindow?

    private override init() {
        super.init()
    }

    func show(bluetoothManager: BluetoothProximityManager) {
        viewModel.bluetoothManager = bluetoothManager
        viewModel.discoveredDevices = []
        viewModel.isScanning = false
        // Track parent window for refocus
        self.parentWindow = NSApp.keyWindow

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
            self?.close()
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

    private func close() {
        viewModel.stopScanning()
        window?.orderOut(nil)
        refocusParent()
    }

    private func refocusParent() {
        if let parent = parentWindow, parent.isVisible {
            parent.makeKeyAndOrderFront(nil)
        }
    }

    func windowWillClose(_ notification: Notification) {
        viewModel.stopScanning()
        refocusParent()
    }
}

/// View model for device scanner
class DeviceScannerViewModel: NSObject, ObservableObject {
    var bluetoothManager: BluetoothProximityManager?
    @Published var discoveredDevices: [DiscoveredDevice] = []
    @Published var isScanning = false

    private var centralManager: CBCentralManager?
    /// Names are attacker-controlled: one seen from several peripherals never binds a device.
    private var blePeripheralsByName: [String: Set<UUID>] = [:]

    func startScanning() {
        guard !isScanning else { return }
        isScanning = true
        discoveredDevices = []
        blePeripheralsByName = [:]

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
                id: UUID(),
                name: name,
                // Display/sort estimate only; -80 when no real reading is available
                rssi: (ioDevice.isConnected() ? RSSI(Int(ioDevice.rawRSSI()))?.dBm : nil) ?? -80,
                isPaired: true,
                classicAddress: ioDevice.addressString.flatMap(BluetoothAddress.init),
                isConnected: ioDevice.isConnected()
            )

            discoveredDevices.append(device)
            logActivity(.bluetooth, "Paired device: \(name) (addr: \(ioDevice.addressString ?? "?"), connected: \(ioDevice.isConnected()))")
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

        // A Classic device without an address could never be detected
        guard let transport = device.transport else {
            logActivity(.bluetooth, "Cannot trust \(device.name): no BLE match and no Bluetooth address")
            return
        }
        let trustedDevice = TrustedDevice(id: device.trustedID, name: device.name, transport: transport)

        // Add device via BluetoothProximityManager
        let added = bluetoothManager.addTrustedDevice(trustedDevice)
        if added {
            logActivity(.bluetooth, "Added device: \(device.name) (classic: \(device.isClassicBluetooth))")
        }
    }

    /// Why `device` can't be added, if it can't (the manager's one rule).
    func refusal(for device: DiscoveredDevice) -> BluetoothProximityManager.Refusal? {
        bluetoothManager?.admission(of: device.trustedID, classicAddress: device.classicAddress)
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
            logActivity(.bluetooth, "Started BLE scanning to identify device types")
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

        let key = name.lowercased()
        let peripherals = blePeripheralsByName[key, default: []].union([peripheral.identifier])
        blePeripheralsByName[key] = peripherals

        // Find matching device in our paired list by name
        // Only update existing paired devices - ignore unpaired BLE devices
        if let index = discoveredDevices.firstIndex(where: { $0.name.lowercased() == key }) {
            var device = discoveredDevices[index]

            if peripherals.count == 1 {
                // Exactly one peripheral advertises this name: track it via BLE RSSI
                device.blePeripheralID = peripheral.identifier
                device.rssi = RSSI.intValue
                logActivity(.bluetooth, "Device \(name) found via BLE, UUID: \(peripheral.identifier)")
            } else if device.blePeripheralID != nil {
                // Another peripheral claims the same name: refuse to guess
                device.blePeripheralID = nil
                logActivity(.bluetooth, "Multiple BLE peripherals named \(name) - keeping Classic tracking")
            }
            discoveredDevices[index] = device
        }
        // Note: Unpaired BLE devices are intentionally ignored - only paired devices shown

        DispatchQueue.main.async {
            self.sortDevices()
        }
    }
}

/// Discovered device model
struct DiscoveredDevice: Identifiable {
    let id: UUID
    let name: String
    var rssi: Int
    let isPaired: Bool
    let classicAddress: BluetoothAddress?
    /// Set only while exactly one BLE peripheral advertises this name
    var blePeripheralID: UUID? = nil
    var isConnected: Bool

    var isClassicBluetooth: Bool { blePeripheralID == nil }

    var trustedID: UUID { blePeripheralID ?? id }

    /// `nil` when the device cannot be tracked at all
    var transport: TrustedDevice.Transport? {
        if blePeripheralID != nil { return .ble }
        return classicAddress.map { .classic(address: $0) }
    }
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
                    let refusal = viewModel.refusal(for: device)
                    DeviceRowButton(
                        device: device,
                        isAlreadyAdded: refusal == .alreadyTrusted,
                        isDisabled: refusal != nil
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
                            Text(device.isClassicBluetooth ? "Classic" : "BLE")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(device.isClassicBluetooth ? Color.orange : Color.blue)
                                .clipShape(Capsule())
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
