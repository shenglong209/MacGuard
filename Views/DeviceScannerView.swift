// DeviceScannerView.swift
// MacGuard - Anti-Theft Alarm for macOS
// Created: 2025-12-18

import SwiftUI
import CoreBluetooth

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
            NSApp.setActivationPolicy(.accessory)
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
        NSApp.setActivationPolicy(.accessory)
    }
}

/// View model for device scanner
class DeviceScannerViewModel: NSObject, ObservableObject {
    var bluetoothManager: BluetoothProximityManager?
    @Published var discoveredDevices: [DiscoveredDevice] = []
    @Published var isScanning = false

    private var centralManager: CBCentralManager?

    func startScanning() {
        guard !isScanning else { return }
        isScanning = true
        discoveredDevices = []

        // Create our own central manager for discovery
        centralManager = CBCentralManager(delegate: self, queue: nil)
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
            // Scan for all peripherals
            central.scanForPeripherals(
                withServices: nil,
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
            )
            print("[Scanner] Started scanning")
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        // Only include devices with names (skip unnamed)
        guard let name = peripheral.name, !name.isEmpty else { return }

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
            print("[Scanner] Found: \(name) (RSSI: \(RSSI))")
        }
    }
}

/// Discovered device model
struct DiscoveredDevice: Identifiable {
    let id: UUID
    let name: String
    let rssi: Int
}

/// Container view
struct DeviceScannerContainerView: View {
    @ObservedObject var viewModel: DeviceScannerViewModel
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                if viewModel.isScanning {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Scanning...")
                        .foregroundColor(.secondary)
                } else {
                    Text("Select your iPhone or Apple Watch")
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding()

            Divider()

            // Device list
            if viewModel.discoveredDevices.isEmpty {
                VStack {
                    Spacer()
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("Looking for nearby devices...")
                        .foregroundColor(.secondary)
                    Text("Make sure Bluetooth is enabled on your device")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List(viewModel.discoveredDevices) { device in
                    Button(action: {
                        viewModel.selectDevice(device)
                        onDismiss()
                    }) {
                        HStack {
                            Image(systemName: deviceIcon(for: device.name))
                                .foregroundColor(.blue)
                            VStack(alignment: .leading) {
                                Text(device.name)
                                Text("\(device.rssi) dBm")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            // Footer
            HStack {
                Button("Cancel") {
                    onDismiss()
                }
                Spacer()
                Button(viewModel.isScanning ? "Stop" : "Rescan") {
                    if viewModel.isScanning {
                        viewModel.stopScanning()
                    } else {
                        viewModel.startScanning()
                    }
                }
            }
            .padding()
        }
        .frame(width: 330, height: 380)
    }

    private func deviceIcon(for name: String) -> String {
        let lowered = name.lowercased()
        if lowered.contains("iphone") {
            return "iphone"
        } else if lowered.contains("watch") {
            return "applewatch"
        } else if lowered.contains("ipad") {
            return "ipad"
        } else if lowered.contains("mac") {
            return "laptopcomputer"
        } else if lowered.contains("airpods") {
            return "airpodspro"
        }
        return "wave.3.right"
    }
}
