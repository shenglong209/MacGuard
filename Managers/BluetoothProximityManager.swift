// BluetoothProximityManager.swift
// MacGuard - Anti-Theft Alarm for macOS
// Created: 2025-12-18

import CoreBluetooth
import IOBluetooth
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
/// Supports both BLE (CoreBluetooth) and Classic Bluetooth (IOBluetooth) devices
class BluetoothProximityManager: NSObject, ObservableObject {
    weak var delegate: BluetoothProximityDelegate?

    // MARK: - Published Properties

    @Published var isBluetoothEnabled = false
    @Published private(set) var trustedDevices: [TrustedDevice] = []
    @Published var isScanning = false
    @Published private(set) var isDeviceNearby = false

    // MARK: - Private Properties

    private var centralManager: CBCentralManager!
    private var connectedPeripherals: [UUID: CBPeripheral] = [:]  // deviceID → peripheral (BLE)
    private var deviceProximityStates: [UUID: Bool] = [:]  // deviceID → isNearby
    private var rssiReadTimer: Timer?

    // BLE device debounce tracking
    private var bleDeviceLastNearby: [UUID: Date] = [:]  // deviceID → last time device was nearby
    private let bleDebounceInterval: TimeInterval = 5.0  // Ignore brief disconnects within 5s

    // RSSI-based proximity debounce (prevents flapping on momentary signal drops)
    private var deviceLastNearbyRSSI: [UUID: Date] = [:]  // deviceID → last time device had nearby RSSI
    private let rssiAwayDebounceInterval: TimeInterval = 3.0  // Require 3s of low RSSI before marking away

    // Classic Bluetooth (IOBluetooth) tracking
    private var classicDeviceLastConnected: [UUID: Bool] = [:]  // deviceID → last known connection state
    private var classicDeviceLastStateChange: [UUID: Date] = [:]  // deviceID → timestamp of last state change
    private let classicDeviceDebounceInterval: TimeInterval = 5.0  // Ignore rapid state changes within 5s

    // IOBluetoothDeviceInquiry for active Classic BT scanning
    private var deviceInquiry: IOBluetoothDeviceInquiry?

    // RSSI unavailable tracking for Classic BT fallback
    private var classicDeviceLastValidRSSI: [UUID: Date] = [:]  // deviceID → last time valid RSSI received
    private let rssiUnavailableTimeout: TimeInterval = 1.0  // Fallback after 1s of no valid RSSI

    // Armed state optimization
    private var isArmed = false
    private let normalPollingInterval: TimeInterval = 1.0
    private let armedPollingInterval: TimeInterval = 0.5

    // Fallback RSSI for connected devices when actual RSSI unavailable
    // Uses -50 dBm (strong signal, conservative near range)
    private let fallbackRSSI: Int = -50

    // Dynamic thresholds from user settings (hysteresis to prevent oscillation)
    private var rssiPresentThreshold: Int {
        AppSettings.shared.effectivePresentThreshold
    }
    private var rssiAwayThreshold: Int {
        AppSettings.shared.effectiveAwayThreshold
    }

    // UserDefaults keys for persistence
    private let trustedDevicesKey = "MacGuard.trustedDevices"
    private let legacyTrustedDeviceKey = "MacGuard.trustedDevice"  // For migration

    // Device limit
    private let maxTrustedDevices = 10

    // MARK: - Logging Helper

    /// Log to ActivityLogManager from non-MainActor context
    private func log(_ category: ActivityLogCategory, _ message: String) {
        Task { @MainActor in
            ActivityLogManager.shared.log(category, message)
        }
    }

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
        setupDeviceInquiry()
        loadTrustedDevices()
    }

    /// Configure IOBluetoothDeviceInquiry for active Classic BT scanning
    private func setupDeviceInquiry() {
        deviceInquiry = IOBluetoothDeviceInquiry(delegate: self)
        deviceInquiry?.updateNewDeviceNames = false  // Skip name resolution for speed
        deviceInquiry?.inquiryLength = 5  // 5-second inquiry cycles
    }

    /// Set armed state to adjust polling frequency
    func setArmedState(_ armed: Bool) {
        guard isArmed != armed else { return }
        isArmed = armed

        // Restart timer with appropriate interval if scanning
        if isScanning {
            rssiReadTimer?.invalidate()
            let interval = armed ? armedPollingInterval : normalPollingInterval
            rssiReadTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                self?.pollAllDevices()
            }
            log(.bluetooth, "Polling interval: \(interval)s (armed: \(armed))")
        }
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
            log(.bluetooth, "Max devices reached (\(maxTrustedDevices))")
            return false
        }
        // Check for duplicate by ID or Bluetooth address
        guard !trustedDevices.contains(where: {
            $0.id == device.id ||
            (device.bluetoothAddress != nil && $0.bluetoothAddress == device.bluetoothAddress)
        }) else {
            log(.bluetooth, "Device already trusted: \(device.name)")
            return false
        }
        trustedDevices.append(device)
        saveTrustedDevices()
        log(.bluetooth, "Added trusted device: \(device.name) (classic: \(device.isClassicBluetooth), total: \(trustedDevices.count))")

        // Handle new device detection based on type
        if centralManager.state == .poweredOn {
            if !isScanning {
                // Not scanning at all - start full scanning
                startScanning()
            } else if !device.isClassicBluetooth {
                // BLE device added while scanning - resume BLE scan (may have stopped)
                centralManager.scanForPeripherals(
                    withServices: nil,
                    options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
                )
                log(.bluetooth, "Resumed BLE scanning for new device: \(device.name)")
            }
            // Classic BT devices will be picked up by next timer poll (within 1 second)
        }
        return true
    }

    /// Remove a specific trusted device
    func removeTrustedDevice(_ device: TrustedDevice) {
        trustedDevices.removeAll { $0.id == device.id }
        deviceProximityStates.removeValue(forKey: device.id)
        bleDeviceLastNearby.removeValue(forKey: device.id)
        deviceLastNearbyRSSI.removeValue(forKey: device.id)
        classicDeviceLastConnected.removeValue(forKey: device.id)
        classicDeviceLastStateChange.removeValue(forKey: device.id)
        classicDeviceLastValidRSSI.removeValue(forKey: device.id)
        saveTrustedDevices()

        // Disconnect peripheral if connected (BLE only)
        if let peripheral = connectedPeripherals.removeValue(forKey: device.id) {
            centralManager.cancelPeripheralConnection(peripheral)
        }

        log(.bluetooth, "Removed trusted device: \(device.name) (remaining: \(trustedDevices.count))")

        // Update overall nearby state
        updateOverallNearbyState()
    }

    /// Remove all trusted devices
    func removeAllTrustedDevices() {
        trustedDevices.removeAll()
        deviceProximityStates.removeAll()
        bleDeviceLastNearby.removeAll()
        deviceLastNearbyRSSI.removeAll()
        classicDeviceLastConnected.removeAll()
        classicDeviceLastStateChange.removeAll()
        classicDeviceLastValidRSSI.removeAll()
        saveTrustedDevices()
        disconnectAllPeripherals()
        isDeviceNearby = false
        log(.bluetooth, "Removed all trusted devices")
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
            log(.bluetooth, "Loaded \(devices.count) trusted devices")
            return
        }

        // Migrate from legacy single device
        if let data = UserDefaults.standard.data(forKey: legacyTrustedDeviceKey),
           let device = try? JSONDecoder().decode(TrustedDevice.self, from: data) {
            trustedDevices = [device]
            saveTrustedDevices()
            UserDefaults.standard.removeObject(forKey: legacyTrustedDeviceKey)
            log(.bluetooth, "Migrated single device to array: \(device.name)")
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
            log(.bluetooth, "Cannot scan - Bluetooth not powered on")
            return
        }

        guard !isScanning else { return }

        // Reset lastRSSI for all devices
        for i in trustedDevices.indices {
            trustedDevices[i].lastRSSI = nil
        }
        deviceProximityStates.removeAll()
        classicDeviceLastConnected.removeAll()
        classicDeviceLastValidRSSI.removeAll()
        isDeviceNearby = false

        // Scan for BLE peripherals
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )

        // Start IOBluetoothDeviceInquiry for Classic BT devices
        if trustedDevices.contains(where: { $0.isClassicBluetooth }) {
            deviceInquiry?.start()
            log(.bluetooth, "Started IOBluetoothDeviceInquiry for Classic BT")
        }

        // Start unified polling timer with appropriate interval
        let interval = isArmed ? armedPollingInterval : normalPollingInterval
        rssiReadTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.pollAllDevices()
        }

        isScanning = true
        log(.bluetooth, "Started scanning for \(trustedDevices.count) trusted devices (interval: \(interval)s)")
    }

    /// Stop scanning for Bluetooth devices
    func stopScanning() {
        guard isScanning else { return }

        centralManager.stopScan()
        rssiReadTimer?.invalidate()
        rssiReadTimer = nil
        deviceInquiry?.stop()

        disconnectAllPeripherals()

        isScanning = false
        isDeviceNearby = false
        log(.bluetooth, "Stopped scanning")
    }

    /// Unified polling for both BLE and Classic Bluetooth devices
    private func pollAllDevices() {
        // Poll BLE devices
        pollBLEDevices()
        // Poll Classic Bluetooth devices
        pollClassicBluetoothDevices()
    }

    private func pollBLEDevices() {
        for (deviceID, peripheral) in connectedPeripherals {
            if peripheral.state == .connected {
                peripheral.readRSSI()
            } else {
                // Device disconnected - apply debounce to prevent rapid oscillation
                let lastNearby = bleDeviceLastNearby[deviceID] ?? .distantPast
                let timeSinceNearby = Date().timeIntervalSince(lastNearby)

                if timeSinceNearby < bleDebounceInterval {
                    // Recently was nearby - debounce the disconnect
                    if let device = trustedDevices.first(where: { $0.id == deviceID }) {
                        log(.bluetooth, "BLE device (\(device.name)) disconnect debounced - ignoring brief disconnect")
                    }
                    continue
                }

                // Enough time passed - mark as away
                updateProximityState(for: deviceID, rssi: -100)
            }
        }
    }

    /// Poll Classic Bluetooth devices using IOBluetooth
    private func pollClassicBluetoothDevices() {
        guard let pairedDevices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return
        }

        for device in trustedDevices where device.isClassicBluetooth {
            guard let address = device.bluetoothAddress else { continue }

            // Find matching IOBluetooth device by address
            guard let ioDevice = pairedDevices.first(where: { $0.addressString == address }) else {
                continue
            }

            let isConnected = ioDevice.isConnected()
            let wasConnected = classicDeviceLastConnected[device.id]
            let lastChange = classicDeviceLastStateChange[device.id] ?? .distantPast
            let timeSinceLastChange = Date().timeIntervalSince(lastChange)

            // First poll for this device - initialize state
            if wasConnected == nil {
                classicDeviceLastConnected[device.id] = isConnected
                classicDeviceLastStateChange[device.id] = Date()

                if isConnected {
                    log(.bluetooth, "Classic device connected: \(device.name)")
                    let rssi = ioDevice.rawRSSI()
                    let effectiveRSSI = (rssi != 127 && rssi != 0) ? Int(rssi) : fallbackRSSI
                    updateProximityState(for: device.id, rssi: effectiveRSSI)
                } else {
                    // Device not connected on first poll - mark as away
                    log(.bluetooth, "Classic device not connected: \(device.name)")
                    updateProximityState(for: device.id, rssi: -100)
                }
                continue
            }

            // Connection state changed - apply debounce to prevent rapid oscillation
            if isConnected != wasConnected {
                // Debounce: Ignore disconnect if it happens within debounce interval of connect
                // This handles AirPods and other devices with flaky connection behavior
                if !isConnected && timeSinceLastChange < classicDeviceDebounceInterval {
                    log(.bluetooth, "Classic device (\(device.name)) disconnect debounced - ignoring rapid state change")
                    continue
                }

                classicDeviceLastConnected[device.id] = isConnected
                classicDeviceLastStateChange[device.id] = Date()

                if isConnected {
                    // Device connected = nearby
                    log(.bluetooth, "Classic device connected: \(device.name)")
                    // Try to get RSSI, fallback to strong signal
                    // Note: rawRSSI() returns 0 or 127 when unavailable
                    let rssi = ioDevice.rawRSSI()
                    let effectiveRSSI = (rssi != 127 && rssi != 0) ? Int(rssi) : fallbackRSSI
                    updateProximityState(for: device.id, rssi: effectiveRSSI)
                } else {
                    // Device disconnected = away
                    log(.bluetooth, "Classic device disconnected: \(device.name)")
                    updateProximityState(for: device.id, rssi: -100)
                }
            } else if isConnected {
                // Device still connected - update RSSI if available
                // Note: rawRSSI() returns 0 or 127 when unavailable
                let rssi = ioDevice.rawRSSI()
                if rssi != 127 && rssi != 0 {
                    // Valid RSSI - update state and timestamp
                    classicDeviceLastValidRSSI[device.id] = Date()
                    updateProximityState(for: device.id, rssi: Int(rssi))
                } else {
                    // RSSI unavailable - check timeout for fallback
                    let lastValid = classicDeviceLastValidRSSI[device.id] ?? .distantPast
                    if Date().timeIntervalSince(lastValid) > rssiUnavailableTimeout {
                        // Timeout - use fallback RSSI for connected device (assume nearby)
                        updateProximityState(for: device.id, rssi: fallbackRSSI)
                    }
                }
                // Update lastSeen
                if let index = trustedDevices.firstIndex(where: { $0.id == device.id }) {
                    trustedDevices[index].lastSeen = Date()
                }
            }
        }
    }

    // MARK: - RSSI Handling

    private func updateProximityState(for deviceID: UUID, rssi: Int) {
        guard let deviceIndex = trustedDevices.firstIndex(where: { $0.id == deviceID }) else { return }

        let wasOverallNearby = isDeviceNearby
        let currentState = deviceProximityStates[deviceID] ?? false

        // Hysteresis logic (per device)
        var newState: Bool
        if currentState {
            newState = rssi >= rssiAwayThreshold  // Stay nearby unless below away threshold
        } else {
            newState = rssi >= rssiPresentThreshold  // Become nearby only above present threshold
        }

        // RSSI-based debounce: if transitioning from nearby→away, require sustained low RSSI
        if currentState && !newState {
            // Check if we've had sustained low RSSI for debounce interval
            let lastNearby = deviceLastNearbyRSSI[deviceID] ?? .distantPast
            let timeSinceNearby = Date().timeIntervalSince(lastNearby)

            if timeSinceNearby < rssiAwayDebounceInterval {
                // Recent nearby RSSI - debounce, keep as nearby
                newState = true
                if let device = trustedDevices.first(where: { $0.id == deviceID }) {
                    log(.bluetooth, "\(device.name) RSSI drop debounced (last nearby: \(String(format: "%.1f", timeSinceNearby))s ago)")
                }
            }
        }

        // Track last time we had "nearby" RSSI (before debounce override)
        if rssi >= rssiAwayThreshold {
            deviceLastNearbyRSSI[deviceID] = Date()
        }

        deviceProximityStates[deviceID] = newState

        // Update runtime data on device
        trustedDevices[deviceIndex].lastRSSI = rssi
        trustedDevices[deviceIndex].lastSeen = Date()

        // Track last nearby time for BLE debounce
        if newState {
            bleDeviceLastNearby[deviceID] = Date()
        }

        // Handle state transitions
        if !currentState && newState {
            // Device became nearby
            log(.bluetooth, "\(trustedDevices[deviceIndex].name) nearby (RSSI: \(rssi))")
            delegate?.trustedDeviceNearby(trustedDevices[deviceIndex])
        } else if currentState && !newState {
            // Device went away
            log(.bluetooth, "\(trustedDevices[deviceIndex].name) away (RSSI: \(rssi))")
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

    /// Check if a specific device is nearby
    func isNearby(_ device: TrustedDevice) -> Bool {
        deviceProximityStates[device.id] ?? false
    }

    /// Get connection status for a specific device
    func connectionStatus(for device: TrustedDevice) -> DeviceConnectionStatus {
        if device.isClassicBluetooth {
            // Classic Bluetooth - check IOBluetooth connection state
            let isConnected = classicDeviceLastConnected[device.id] ?? false
            if isConnected {
                return .connected
            }
            return isScanning ? .searching : .disconnected
        } else {
            // BLE - check CBPeripheral state
            guard let peripheral = connectedPeripherals[device.id] else {
                return isScanning ? .searching : .disconnected
            }
            switch peripheral.state {
            case .connected: return .connected
            case .connecting: return .connecting
            default: return isScanning ? .searching : .disconnected
            }
        }
    }
}

/// Connection status for a trusted device
enum DeviceConnectionStatus {
    case connected
    case connecting
    case searching
    case disconnected

    var label: String {
        switch self {
        case .connected: return "Connected"
        case .connecting: return "Connecting"
        case .searching: return "Searching"
        case .disconnected: return "Disconnected"
        }
    }

    var icon: String {
        switch self {
        case .connected: return "checkmark.circle.fill"
        case .connecting: return "circle.dotted"
        case .searching: return "magnifyingglass"
        case .disconnected: return "circle"
        }
    }

    var color: String {
        switch self {
        case .connected: return "green"
        case .connecting, .searching: return "orange"
        case .disconnected: return "gray"
        }
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
        log(.bluetooth, "State changed: \(stateName)")

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
        // Check if this peripheral matches ANY BLE trusted device
        guard let matchingDevice = trustedDevices.first(where: {
            !$0.isClassicBluetooth && $0.id == peripheral.identifier
        }) else {
            return
        }

        // Connect if not already connected
        if connectedPeripherals[matchingDevice.id] == nil {
            log(.bluetooth, "Connecting to BLE device: \(matchingDevice.name)")
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
        log(.bluetooth, "Connected to: \(peripheral.name ?? "Unknown")")

        // Check if all BLE trusted devices are connected - if so, stop BLE scanning to save CPU
        let allBLEConnected = trustedDevices.filter { !$0.isClassicBluetooth }.allSatisfy { device in
            connectedPeripherals[device.id]?.state == .connected
        }
        if allBLEConnected && trustedDevices.contains(where: { !$0.isClassicBluetooth }) {
            centralManager.stopScan()
            log(.bluetooth, "All BLE devices connected - stopped BLE scanning")
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard let deviceID = trustedDevices.first(where: { $0.id == peripheral.identifier })?.id else { return }

        log(.bluetooth, "Disconnected: \(peripheral.name ?? "Unknown")")
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
            log(.bluetooth, "Attempting reconnect to: \(peripheral.name ?? "Unknown")")
        }

        // Check if all devices now away
        if areAllDevicesAway && !trustedDevices.isEmpty {
            delegate?.allTrustedDevicesAway()
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        log(.bluetooth, "Failed to connect: \(error?.localizedDescription ?? "unknown")")
    }
}

// MARK: - CBPeripheralDelegate

extension BluetoothProximityManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard error == nil else {
            log(.bluetooth, "RSSI read error: \(error!.localizedDescription)")
            return
        }
        updateProximityState(for: peripheral.identifier, rssi: RSSI.intValue)
    }
}

// MARK: - IOBluetoothDeviceInquiryDelegate

extension BluetoothProximityManager: IOBluetoothDeviceInquiryDelegate {
    /// Device discovered during inquiry - provides fresh RSSI
    func deviceInquiryDeviceFound(_ sender: IOBluetoothDeviceInquiry!, device: IOBluetoothDevice!) {
        guard let address = device.addressString else { return }

        // Get RSSI value before dispatching to main thread
        let rssi = device.rawRSSI()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Check if this is a trusted Classic BT device (filter early)
            guard let trustedDevice = self.trustedDevices.first(where: {
                $0.isClassicBluetooth && $0.bluetoothAddress == address
            }) else { return }

            // Use fresh RSSI from inquiry result
            if rssi != 127 && rssi != 0 {
                self.classicDeviceLastValidRSSI[trustedDevice.id] = Date()
                self.updateProximityState(for: trustedDevice.id, rssi: Int(rssi))
                self.log(.bluetooth, "Inquiry RSSI for \(trustedDevice.name): \(rssi) dBm")
            }
        }
    }

    /// Inquiry completed - restart for continuous monitoring
    func deviceInquiryComplete(_ sender: IOBluetoothDeviceInquiry!, error: IOReturn, aborted: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // Restart inquiry for continuous monitoring if still scanning
            if self.isScanning && !aborted {
                sender.start()
            }
        }
    }

    /// Optional: Called when name resolution starts (not used, but required for protocol)
    func deviceInquiryUpdatingDeviceNamesStarted(_ sender: IOBluetoothDeviceInquiry!, devicesRemaining: UInt32) {
        // Not used - we disabled name updates for speed
    }

    /// Optional: Called when device name is updated
    func deviceInquiryDeviceNameUpdated(_ sender: IOBluetoothDeviceInquiry!, device: IOBluetoothDevice!, devicesRemaining: UInt32) {
        // Not used - we disabled name updates for speed
    }
}
