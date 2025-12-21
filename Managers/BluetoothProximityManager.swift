// BluetoothProximityManager.swift
// MacGuard - Anti-Theft Alarm for macOS
// Created: 2025-12-18

import CoreBluetooth
import Combine

/// Protocol for receiving Bluetooth proximity events
protocol BluetoothProximityDelegate: AnyObject {
    /// Called when trusted device comes within range
    func trustedDeviceNearby(_ device: TrustedDevice)
    /// Called when trusted device leaves range
    func trustedDeviceAway(_ device: TrustedDevice)
    /// Called when Bluetooth state changes
    func bluetoothStateChanged(_ state: CBManagerState)
}

/// Manages Bluetooth proximity detection for trusted devices
class BluetoothProximityManager: NSObject, ObservableObject {
    weak var delegate: BluetoothProximityDelegate?

    // MARK: - Published Properties

    @Published var isBluetoothEnabled = false
    @Published private(set) var trustedDevice: TrustedDevice?
    @Published var isScanning = false
    @Published private(set) var isDeviceNearby = false

    // MARK: - Private Properties

    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var rssiReadTimer: Timer?

    // Dynamic thresholds from user settings (hysteresis to prevent oscillation)
    private var rssiPresentThreshold: Int {
        AppSettings.shared.proximityDistance.presentThreshold
    }
    private var rssiAwayThreshold: Int {
        AppSettings.shared.proximityDistance.awayThreshold
    }

    // UserDefaults key for persistence
    private let trustedDeviceKey = "MacGuard.trustedDevice"

    // MARK: - Initialization

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
        loadTrustedDevice()
    }

    /// Start scanning if trusted device exists (called when Bluetooth powers on)
    private func startScanningIfNeeded() {
        guard trustedDevice != nil, centralManager.state == .poweredOn else { return }
        startScanning()
    }

    // MARK: - Trusted Device Management

    /// Set the single trusted device
    func setTrustedDevice(_ peripheral: CBPeripheral) {
        let device = TrustedDevice(
            id: peripheral.identifier,
            name: peripheral.name ?? "Unknown Device"
        )
        trustedDevice = device
        saveTrustedDevice()
        print("[Bluetooth] Trusted device set: \(device.name)")
    }

    /// Remove the trusted device
    func removeTrustedDevice() {
        trustedDevice = nil
        UserDefaults.standard.removeObject(forKey: trustedDeviceKey)
        print("[Bluetooth] Trusted device removed")
    }

    /// Reload trusted device from UserDefaults (called after external update)
    func reloadTrustedDevice() {
        loadTrustedDevice()
        // Start scanning for the newly loaded device
        startScanningIfNeeded()
    }

    private func loadTrustedDevice() {
        guard let data = UserDefaults.standard.data(forKey: trustedDeviceKey),
              let device = try? JSONDecoder().decode(TrustedDevice.self, from: data) else {
            return
        }
        trustedDevice = device
        print("[Bluetooth] Loaded trusted device: \(device.name)")
    }

    private func saveTrustedDevice() {
        guard let device = trustedDevice,
              let data = try? JSONEncoder().encode(device) else {
            return
        }
        UserDefaults.standard.set(data, forKey: trustedDeviceKey)
    }

    // MARK: - Scanning

    /// Start scanning for Bluetooth devices
    func startScanning() {
        guard centralManager.state == .poweredOn else {
            print("[Bluetooth] Cannot scan - Bluetooth not powered on")
            return
        }

        guard !isScanning else { return }

        // Reset lastRSSI to ensure first reading triggers state evaluation
        if var device = trustedDevice {
            device.lastRSSI = nil
            trustedDevice = device
        }
        isDeviceNearby = false

        // Scan with duplicates to get continuous RSSI updates
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )

        // Start RSSI polling for connected devices
        rssiReadTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.pollConnectedDeviceRSSI()
        }

        isScanning = true
        print("[Bluetooth] Started scanning for devices")
    }

    /// Stop scanning for Bluetooth devices
    func stopScanning() {
        guard isScanning else { return }

        centralManager.stopScan()
        rssiReadTimer?.invalidate()
        rssiReadTimer = nil

        // Disconnect if connected
        if let peripheral = connectedPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
            connectedPeripheral = nil
        }

        isScanning = false
        isDeviceNearby = false
        print("[Bluetooth] Stopped scanning")
    }

    private func pollConnectedDeviceRSSI() {
        connectedPeripheral?.readRSSI()
    }

    // MARK: - RSSI Handling

    private func handleRSSI(_ rssi: Int, for deviceID: UUID) {
        guard var device = trustedDevice, device.id == deviceID else { return }

        let previousRSSI = device.lastRSSI
        device.lastRSSI = rssi
        device.lastSeen = Date()
        trustedDevice = device

        // Hysteresis logic to prevent oscillation
        let wasNearby = (previousRSSI ?? -100) > rssiAwayThreshold
        let isNearby = rssi > rssiPresentThreshold

        // Transition to nearby: either clean transition OR current state is false but RSSI shows nearby
        if (!wasNearby && isNearby) || (!isDeviceNearby && isNearby) {
            if !isDeviceNearby {
                isDeviceNearby = true
                print("[Bluetooth] Trusted device nearby (RSSI: \(rssi))")
                delegate?.trustedDeviceNearby(device)
            }
        } else if wasNearby && rssi < rssiAwayThreshold {
            isDeviceNearby = false
            print("[Bluetooth] Trusted device away (RSSI: \(rssi))")
            delegate?.trustedDeviceAway(device)
        }
    }

    /// Check if trusted device is currently nearby
    func isTrustedDeviceNearby() -> Bool {
        isDeviceNearby
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothProximityManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        isBluetoothEnabled = central.state == .poweredOn

        let stateName: String
        switch central.state {
        case .poweredOn: stateName = "poweredOn"
        case .poweredOff: stateName = "poweredOff"
        case .resetting: stateName = "resetting"
        case .unauthorized: stateName = "unauthorized"
        case .unsupported: stateName = "unsupported"
        case .unknown: stateName = "unknown"
        @unknown default: stateName = "unknown"
        }
        print("[Bluetooth] State changed: \(stateName)")

        // Auto-start scanning when Bluetooth powers on and trusted device exists
        if central.state == .poweredOn {
            startScanningIfNeeded()
        }

        delegate?.bluetoothStateChanged(central.state)
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        // Only process if this is our trusted device
        guard let device = trustedDevice, device.id == peripheral.identifier else { return }

        // Connect for more reliable RSSI readings
        if connectedPeripheral == nil {
            peripheral.delegate = self
            centralManager.connect(peripheral, options: nil)
        }

        handleRSSI(RSSI.intValue, for: peripheral.identifier)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedPeripheral = peripheral
        peripheral.readRSSI()
        print("[Bluetooth] Connected to trusted device")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectedPeripheral = nil
        print("[Bluetooth] Disconnected from trusted device")

        // Reconnect if still trusted and scanning
        if isScanning, let device = trustedDevice, device.id == peripheral.identifier {
            centralManager.connect(peripheral, options: nil)
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("[Bluetooth] Failed to connect: \(error?.localizedDescription ?? "unknown")")
    }
}

// MARK: - CBPeripheralDelegate

extension BluetoothProximityManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard error == nil else {
            print("[Bluetooth] RSSI read error: \(error!.localizedDescription)")
            return
        }
        handleRSSI(RSSI.intValue, for: peripheral.identifier)
    }
}
