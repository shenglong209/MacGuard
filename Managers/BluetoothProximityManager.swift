// BluetoothProximityManager.swift
// MacGuard - Anti-Theft Alarm for macOS
// Created: 2025-12-18

import CoreBluetooth
import Combine

/// Protocol for receiving Bluetooth proximity events
protocol BluetoothProximityDelegate: AnyObject {
    /// Called when any trusted device comes within range
    func trustedDeviceNearby(_ device: TrustedDevice)
    /// Called when a specific trusted device leaves range
    func trustedDeviceAway(_ device: TrustedDevice)
    /// Called when all trusted devices are away
    func allTrustedDevicesAway()
    /// Called when Bluetooth state changes
    func bluetoothStateChanged(_ state: CBManagerState)
}

/// Manages Bluetooth proximity detection for multiple trusted devices
class BluetoothProximityManager: NSObject, ObservableObject {
    weak var delegate: BluetoothProximityDelegate?

    // MARK: - Published Properties

    @Published var isBluetoothEnabled = false
    @Published private(set) var trustedDevices: [TrustedDevice] = []
    @Published var isScanning = false
    @Published private(set) var isDeviceNearby = false

    // MARK: - Private Properties

    private var centralManager: CBCentralManager!
    private var connectedPeripherals: [UUID: CBPeripheral] = [:]  // deviceID → peripheral
    private var deviceProximityStates: [UUID: Bool] = [:]  // deviceID → isNearby
    private var rssiReadTimer: Timer?

    // Dynamic thresholds from user settings (hysteresis to prevent oscillation)
    private var rssiPresentThreshold: Int {
        AppSettings.shared.proximityDistance.presentThreshold
    }
    private var rssiAwayThreshold: Int {
        AppSettings.shared.proximityDistance.awayThreshold
    }

    // UserDefaults keys for persistence
    private let trustedDevicesKey = "MacGuard.trustedDevices"
    private let legacyTrustedDeviceKey = "MacGuard.trustedDevice"  // For migration

    // Device limit
    private let maxTrustedDevices = 10

    // MARK: - Computed Properties

    /// Backward compatibility: returns first trusted device
    var trustedDevice: TrustedDevice? {
        trustedDevices.first
    }

    /// ALL devices away = away (for auto-arm logic)
    var areAllDevicesAway: Bool {
        guard !trustedDevices.isEmpty else { return false }
        return deviceProximityStates.values.allSatisfy { !$0 }
    }

    // MARK: - Initialization

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
        loadTrustedDevices()
    }

    /// Start scanning if trusted devices exist (called when Bluetooth powers on)
    private func startScanningIfNeeded() {
        guard !trustedDevices.isEmpty, centralManager.state == .poweredOn else { return }
        startScanning()
    }

    // MARK: - Trusted Device Management

    /// Add a trusted device (returns false if max reached or duplicate)
    @discardableResult
    func addTrustedDevice(_ device: TrustedDevice) -> Bool {
        guard trustedDevices.count < maxTrustedDevices else {
            print("[Bluetooth] Max devices reached (\(maxTrustedDevices))")
            return false
        }
        guard !trustedDevices.contains(where: { $0.id == device.id }) else {
            print("[Bluetooth] Device already trusted: \(device.name)")
            return false
        }
        trustedDevices.append(device)
        saveTrustedDevices()
        print("[Bluetooth] Added trusted device: \(device.name) (total: \(trustedDevices.count))")

        // Start scanning for new device if Bluetooth is on
        if centralManager.state == .poweredOn && !isScanning {
            startScanning()
        }
        return true
    }

    /// Remove a specific trusted device
    func removeTrustedDevice(_ device: TrustedDevice) {
        trustedDevices.removeAll { $0.id == device.id }
        deviceProximityStates.removeValue(forKey: device.id)
        saveTrustedDevices()

        // Disconnect peripheral if connected
        if let peripheral = connectedPeripherals.removeValue(forKey: device.id) {
            centralManager.cancelPeripheralConnection(peripheral)
        }

        print("[Bluetooth] Removed trusted device: \(device.name) (remaining: \(trustedDevices.count))")

        // Update overall nearby state
        updateOverallNearbyState()
    }

    /// Remove all trusted devices
    func removeAllTrustedDevices() {
        trustedDevices.removeAll()
        deviceProximityStates.removeAll()
        saveTrustedDevices()
        disconnectAllPeripherals()
        isDeviceNearby = false
        print("[Bluetooth] Removed all trusted devices")
    }

    /// Backward compatibility: remove the single device (removes all)
    func removeTrustedDevice() {
        removeAllTrustedDevices()
    }

    /// Reload trusted devices from UserDefaults (called after external update)
    func reloadTrustedDevices() {
        loadTrustedDevices()
        startScanningIfNeeded()
    }

    private func loadTrustedDevices() {
        // Try new key first
        if let data = UserDefaults.standard.data(forKey: trustedDevicesKey),
           let devices = try? JSONDecoder().decode([TrustedDevice].self, from: data) {
            trustedDevices = devices
            print("[Bluetooth] Loaded \(devices.count) trusted devices")
            return
        }

        // Migrate from legacy single device
        if let data = UserDefaults.standard.data(forKey: legacyTrustedDeviceKey),
           let device = try? JSONDecoder().decode(TrustedDevice.self, from: data) {
            trustedDevices = [device]
            saveTrustedDevices()
            UserDefaults.standard.removeObject(forKey: legacyTrustedDeviceKey)
            print("[Bluetooth] Migrated single device to array: \(device.name)")
        }
    }

    private func saveTrustedDevices() {
        guard let data = try? JSONEncoder().encode(trustedDevices) else { return }
        UserDefaults.standard.set(data, forKey: trustedDevicesKey)
    }

    private func disconnectAllPeripherals() {
        for peripheral in connectedPeripherals.values {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        connectedPeripherals.removeAll()
    }

    // MARK: - Scanning

    /// Start scanning for Bluetooth devices
    func startScanning() {
        guard centralManager.state == .poweredOn else {
            print("[Bluetooth] Cannot scan - Bluetooth not powered on")
            return
        }

        guard !isScanning else { return }

        // Reset lastRSSI for all devices
        for i in trustedDevices.indices {
            trustedDevices[i].lastRSSI = nil
        }
        deviceProximityStates.removeAll()
        isDeviceNearby = false

        // Scan without duplicates - RSSI updates come from connected device's readRSSI()
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )

        // Start RSSI polling for connected devices
        rssiReadTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.pollConnectedDevicesRSSI()
        }

        isScanning = true
        print("[Bluetooth] Started scanning for \(trustedDevices.count) trusted devices")
    }

    /// Stop scanning for Bluetooth devices
    func stopScanning() {
        guard isScanning else { return }

        centralManager.stopScan()
        rssiReadTimer?.invalidate()
        rssiReadTimer = nil

        disconnectAllPeripherals()

        isScanning = false
        isDeviceNearby = false
        print("[Bluetooth] Stopped scanning")
    }

    private func pollConnectedDevicesRSSI() {
        for (deviceID, peripheral) in connectedPeripherals {
            if peripheral.state == .connected {
                peripheral.readRSSI()
            } else {
                // Device disconnected - mark as away
                updateProximityState(for: deviceID, rssi: -100)
            }
        }
    }

    // MARK: - RSSI Handling

    private func updateProximityState(for deviceID: UUID, rssi: Int) {
        guard let deviceIndex = trustedDevices.firstIndex(where: { $0.id == deviceID }) else { return }

        let wasOverallNearby = isDeviceNearby
        let currentState = deviceProximityStates[deviceID] ?? false

        // Hysteresis logic (per device)
        let newState: Bool
        if currentState {
            newState = rssi >= rssiAwayThreshold  // Stay nearby unless below away threshold
        } else {
            newState = rssi >= rssiPresentThreshold  // Become nearby only above present threshold
        }

        deviceProximityStates[deviceID] = newState

        // Update runtime data on device
        trustedDevices[deviceIndex].lastRSSI = rssi
        trustedDevices[deviceIndex].lastSeen = Date()

        // Handle state transitions
        if !currentState && newState {
            // Device became nearby
            print("[Bluetooth] \(trustedDevices[deviceIndex].name) nearby (RSSI: \(rssi))")
            delegate?.trustedDeviceNearby(trustedDevices[deviceIndex])
        } else if currentState && !newState {
            // Device went away
            print("[Bluetooth] \(trustedDevices[deviceIndex].name) away (RSSI: \(rssi))")
            delegate?.trustedDeviceAway(trustedDevices[deviceIndex])
        }

        // Update overall nearby state
        updateOverallNearbyState()

        // Check if all devices now away (for auto-arm)
        let isNowOverallNearby = isDeviceNearby
        if wasOverallNearby && !isNowOverallNearby && areAllDevicesAway {
            delegate?.allTrustedDevicesAway()
        }
    }

    private func updateOverallNearbyState() {
        // ANY device nearby = nearby
        isDeviceNearby = deviceProximityStates.values.contains(true)
    }

    /// Check if any trusted device is currently nearby
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

        // Auto-start scanning when Bluetooth powers on and trusted devices exist
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
        // Check if this peripheral matches ANY trusted device
        guard let matchingDevice = trustedDevices.first(where: { $0.id == peripheral.identifier }) else {
            return
        }

        // Connect if not already connected
        if connectedPeripherals[matchingDevice.id] == nil {
            print("[Bluetooth] Connecting to: \(matchingDevice.name)")
            peripheral.delegate = self
            connectedPeripherals[matchingDevice.id] = peripheral
            centralManager.connect(peripheral, options: nil)
        }

        updateProximityState(for: peripheral.identifier, rssi: RSSI.intValue)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard let deviceID = trustedDevices.first(where: { $0.id == peripheral.identifier })?.id else { return }
        connectedPeripherals[deviceID] = peripheral
        peripheral.readRSSI()
        print("[Bluetooth] Connected to: \(peripheral.name ?? "Unknown")")

        // Check if all trusted devices are connected - if so, stop scanning to save CPU
        let allConnected = trustedDevices.allSatisfy { device in
            connectedPeripherals[device.id]?.state == .connected
        }
        if allConnected && !trustedDevices.isEmpty {
            centralManager.stopScan()
            print("[Bluetooth] All devices connected - stopped scanning")
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard let deviceID = trustedDevices.first(where: { $0.id == peripheral.identifier })?.id else { return }

        print("[Bluetooth] Disconnected: \(peripheral.name ?? "Unknown")")
        connectedPeripherals.removeValue(forKey: deviceID)
        deviceProximityStates[deviceID] = false

        // Update overall state
        updateOverallNearbyState()

        // Reconnect if still trusted and scanning
        if isScanning, trustedDevices.contains(where: { $0.id == deviceID }) {
            // Resume scanning to rediscover device
            centralManager.scanForPeripherals(
                withServices: nil,
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
            )
            centralManager.connect(peripheral, options: nil)
            print("[Bluetooth] Attempting reconnect to: \(peripheral.name ?? "Unknown")")
        }

        // Check if all devices now away
        if areAllDevicesAway && !trustedDevices.isEmpty {
            delegate?.allTrustedDevicesAway()
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
        updateProximityState(for: peripheral.identifier, rssi: RSSI.intValue)
    }
}
