// BluetoothProximityManager.swift
// MacGuard - Anti-Theft Alarm for macOS
// Created: 2025-12-18

import CoreBluetooth
import IOBluetooth
import Combine

struct DeviceTracking: Equatable {
    var proximity = ProximityTracker()
    var classicLink = ClassicLinkTracker()

    mutating func resetForScan() {
        proximity.resetForScan()
        classicLink.resetForScan()
    }
}

/// Manages Bluetooth proximity detection for multiple trusted devices
/// I/O shell: parses callbacks into `Observation`s; `ProximityTracker` decides.
class BluetoothProximityManager: NSObject, ObservableObject {
    var onInput: (AlarmInput) -> Void = { _ in }

    enum Refusal { case alreadyTrusted, full }

    static let maxTrustedDevices = 10

    // MARK: - Published Properties

    @Published var isBluetoothEnabled = false
    @Published private(set) var trustedDevices: [TrustedDevice] = []
    @Published private(set) var tracking: [UUID: DeviceTracking] = [:]
    /// Exists exactly while scanning.
    @Published private var pollTimer: Timer?

    var isScanning: Bool { pollTimer != nil }

    // MARK: - Private Properties

    private var centralManager: CBCentralManager!
    private var connectedPeripherals: [UUID: CBPeripheral] = [:]  // deviceID → peripheral (BLE)

    // IOBluetoothDeviceInquiry for active Classic BT scanning
    private var deviceInquiry: IOBluetoothDeviceInquiry?

    // Armed state optimization
    private var isArmed = false
    private let normalPollingInterval: TimeInterval = 1.0
    private let armedPollingInterval: TimeInterval = 0.5

    // BT state recovery cooldown (prevents false "away" after BT powers on)
    private var recoveryCooldown = RecoveryCooldown()

    // BT stability tracking (prevents auto-arm during BT instability)
    private var btStateChangeCount: Int = 0
    private var btStateChangeWindowStart: Date = Date()
    private let btStabilityWindow: TimeInterval = 300.0  // 5 min window
    private let btStabilityThreshold: Int = 3  // 3+ changes = unstable

    private var isLowPower: Bool { ProcessInfo.processInfo.isLowPowerModeEnabled }
    private var lowPowerSuffix: String { isLowPower ? " (low power)" : "" }

    // Dynamic thresholds from user settings (hysteresis to prevent oscillation)
    private var thresholds: ProximityThresholds {
        AppSettings.shared.proximityThresholds
    }

    // UserDefaults keys for persistence
    private let trustedDevicesKey = "MacGuard.trustedDevices"
    private let legacyTrustedDeviceKey = "MacGuard.trustedDevice"  // For migration


    // MARK: - Computed Properties

    /// Devices not observed since scanning started are ignored.
    var areAllDevicesAway: Bool {
        guard !trustedDevices.isEmpty else { return false }
        return tracking.values
            .map(\.proximity.proximity)
            .filter { $0 != .unobserved }
            .allSatisfy { $0 == .away }
    }

    /// Check if Bluetooth is stable (few state changes, powered on)
    var isBluetoothStable: Bool {
        btStateChangeCount < btStabilityThreshold && centralManager.state == .poweredOn
    }

    private var anyDeviceNearby: Bool {
        isScanning && tracking.values.contains { $0.proximity.isNearby }
    }

    private func device(_ id: UUID) -> TrustedDevice? {
        trustedDevices.first { $0.id == id }
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
        if isScanning {
            schedulePolling()
            logActivity(.bluetooth, "Polling interval: \(pollingInterval)s (armed: \(armed))")
        }
    }

    private var pollingInterval: TimeInterval { isArmed ? armedPollingInterval : normalPollingInterval }

    private func schedulePolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            self?.pollAllDevices()
        }
    }

    private func scanForBLE() {
        centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    /// Start scanning if trusted devices exist (called when Bluetooth powers on)
    private func startScanningIfNeeded() {
        guard !trustedDevices.isEmpty, centralManager.state == .poweredOn else { return }
        startScanning()
    }

    // MARK: - Trusted Device Management

    /// Why a device can't be trusted, if it can't: already trusted (same id or
    /// Classic address) or the list is full.
    func admission(of id: UUID, classicAddress: BluetoothAddress?) -> Refusal? {
        if trustedDevices.contains(where: { $0.id == id || (classicAddress != nil && $0.classicAddress == classicAddress) }) {
            return .alreadyTrusted
        }
        return trustedDevices.count >= Self.maxTrustedDevices ? .full : nil
    }

    @discardableResult
    func addTrustedDevice(_ device: TrustedDevice) -> Bool {
        switch admission(of: device.id, classicAddress: device.classicAddress) {
        case .alreadyTrusted?:
            logActivity(.bluetooth, "Device already trusted: \(device.name)")
            return false
        case .full?:
            logActivity(.bluetooth, "Max devices reached (\(Self.maxTrustedDevices))")
            return false
        case nil:
            break
        }
        trustedDevices.append(device)
        saveTrustedDevices()
        logActivity(.bluetooth, "Added trusted device: \(device.name) (classic: \(device.isClassicBluetooth), total: \(trustedDevices.count))")

        if centralManager.state == .poweredOn {
            if !isScanning {
                startScanning()
            } else if !device.isClassicBluetooth {
                // BLE scanning stops once every BLE device is connected
                scanForBLE()
                logActivity(.bluetooth, "Resumed BLE scanning for new device: \(device.name)")
            }
            // Classic BT devices will be picked up by next timer poll (within 1 second)
        }
        return true
    }

    /// Remove a specific trusted device
    func removeTrustedDevice(_ device: TrustedDevice) {
        trustedDevices.removeAll { $0.id == device.id }
        tracking.removeValue(forKey: device.id)
        saveTrustedDevices()

        // Disconnect peripheral if connected (BLE only)
        if let peripheral = connectedPeripherals.removeValue(forKey: device.id) {
            centralManager.cancelPeripheralConnection(peripheral)
        }

        logActivity(.bluetooth, "Removed trusted device: \(device.name) (remaining: \(trustedDevices.count))")
    }

    /// Remove all trusted devices
    func removeAllTrustedDevices() {
        trustedDevices.removeAll()
        tracking.removeAll()
        saveTrustedDevices()
        disconnectAllPeripherals()
        logActivity(.bluetooth, "Removed all trusted devices")
    }

    private func loadTrustedDevices() {
        // Try new key first
        if let data = UserDefaults.standard.data(forKey: trustedDevicesKey),
           let devices = try? JSONDecoder().decode([TrustedDevice].self, from: data) {
            trustedDevices = devices
            logActivity(.bluetooth, "Loaded \(devices.count) trusted devices")
            return
        }

        // Migrate from legacy single device
        if let data = UserDefaults.standard.data(forKey: legacyTrustedDeviceKey),
           let device = try? JSONDecoder().decode(TrustedDevice.self, from: data) {
            trustedDevices = [device]
            saveTrustedDevices()
            UserDefaults.standard.removeObject(forKey: legacyTrustedDeviceKey)
            logActivity(.bluetooth, "Migrated single device to array: \(device.name)")
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
            logActivity(.bluetooth, "Cannot scan - Bluetooth not powered on")
            return
        }

        guard !isScanning else { return }

        for id in tracking.keys {
            tracking[id]?.resetForScan()
        }

        scanForBLE()

        if trustedDevices.contains(where: { $0.isClassicBluetooth }) {
            deviceInquiry?.start()
            logActivity(.bluetooth, "Started IOBluetoothDeviceInquiry for Classic BT")
        }

        schedulePolling()
        logActivity(.bluetooth, "Started scanning for \(trustedDevices.count) trusted devices (interval: \(pollingInterval)s)")
    }

    /// Stop scanning for Bluetooth devices
    func stopScanning() {
        guard let pollTimer else { return }

        centralManager.stopScan()
        pollTimer.invalidate()
        self.pollTimer = nil
        deviceInquiry?.stop()

        disconnectAllPeripherals()

        logActivity(.bluetooth, "Stopped scanning")
    }

    /// Unified polling for both BLE and Classic Bluetooth devices
    private func pollAllDevices() {
        pollBLEDevices()
        pollClassicBluetoothDevices()
    }

    private func pollBLEDevices() {
        let now = Date()
        for (deviceID, peripheral) in connectedPeripherals {
            if peripheral.state == .connected {
                peripheral.readRSSI()
                continue
            }
            if tracking[deviceID, default: DeviceTracking()].proximity.shouldDebounceDisconnect(at: now, lowPower: isLowPower) {
                if let device = device(deviceID) {
                    logActivity(.bluetooth, "BLE device (\(device.name)) disconnect debounced - ignoring brief disconnect\(lowPowerSuffix)")
                }
                continue
            }
            observe(.disconnected, for: deviceID, at: now)
        }
    }

    /// Poll Classic Bluetooth devices using IOBluetooth
    private func pollClassicBluetoothDevices() {
        guard let pairedDevices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return
        }
        let now = Date()

        for device in trustedDevices {
            guard case .classic(let address) = device.transport,
                  let ioDevice = pairedDevices.first(where: {
                      $0.addressString.flatMap(BluetoothAddress.init) == address
                  }) else { continue }

            let result = tracking[device.id, default: DeviceTracking()].classicLink.poll(
                isConnected: ioDevice.isConnected(),
                rssi: RSSI(Int(ioDevice.rawRSSI())),
                at: now,
                lowPower: isLowPower
            )
            switch result {
            case .none:
                break
            case .disconnectDebounced:
                logActivity(.bluetooth, "Classic device (\(device.name)) disconnect debounced - ignoring rapid state change\(lowPowerSuffix)")
            case .observe(let observation, let event):
                switch event {
                case .initiallyConnected?, .connected?: logActivity(.bluetooth, "Classic device connected: \(device.name)")
                case .initiallyDisconnected?: logActivity(.bluetooth, "Classic device not connected: \(device.name)")
                case .disconnected?: logActivity(.bluetooth, "Classic device disconnected: \(device.name)")
                case nil: break
                }
                observe(observation, for: device.id, at: now)
            }
        }
    }

    // MARK: - Observation Handling

    private func observe(_ observation: Observation, for deviceID: UUID, at now: Date) {
        guard let device = device(deviceID) else { return }

        let wasOverallNearby = anyDeviceNearby
        let change = tracking[deviceID, default: DeviceTracking()].proximity.observe(
            observation,
            at: now,
            thresholds: thresholds,
            lowPower: isLowPower,
            recoveryCooldownActive: recoveryCooldown.isActive(at: now)
        )

        let reading = observation.rssi.map(\.description) ?? "\(observation)"
        switch change {
        case .becameNearby:
            logActivity(.bluetooth, "\(device.name) nearby (RSSI: \(reading))")
            onInput(.trustedDeviceNearby(name: device.name))
        case .becameAway:
            logActivity(.bluetooth, "\(device.name) away (RSSI: \(reading))")
            onInput(.trustedDeviceAway(name: device.name))
        case .awaySuppressedByCooldown:
            logActivity(.bluetooth, "\(device.name) away blocked (BT recovery cooldown)")
        case .awayDebounced(let since):
            logActivity(.bluetooth, "\(device.name) RSSI drop debounced (last nearby: \(String(format: "%.1f", since))s ago)\(lowPowerSuffix)")
        case .unchanged:
            break
        }

        // Check if all devices now away (for auto-arm)
        if wasOverallNearby && !anyDeviceNearby && areAllDevicesAway {
            onInput(.allTrustedDevicesAway)
        }
    }

    /// Proximity assumed during the BT recovery cooldown vouches for nobody.
    func isTrustedDeviceNearby() -> Bool {
        recoveryCooldown.vouchesForPresence(anyDeviceNearby, at: Date())
    }

    var areAllDevicesNearby: Bool {
        !trustedDevices.isEmpty
            && recoveryCooldown.vouchesForPresence(trustedDevices.allSatisfy(isNearby), at: Date())
    }

    /// Check if a specific device is nearby
    func isNearby(_ device: TrustedDevice) -> Bool {
        tracking[device.id]?.proximity.isNearby ?? false
    }

    func lastObservation(for device: TrustedDevice) -> Observation? {
        tracking[device.id]?.proximity.lastObservation
    }

    /// Get connection status for a specific device
    func connectionStatus(for device: TrustedDevice) -> DeviceConnectionStatus {
        let unconnected: DeviceConnectionStatus = isScanning ? .searching : .disconnected
        if device.isClassicBluetooth {
            return tracking[device.id]?.classicLink.connected == true ? .connected : unconnected
        }
        switch connectedPeripherals[device.id]?.state {
        case .connected?: return .connected
        case .connecting?: return .connecting
        default: return unconnected
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

        // Track BT state changes for stability detection
        btStateChangeCount += 1
        if Date().timeIntervalSince(btStateChangeWindowStart) > btStabilityWindow {
            btStateChangeCount = 1
            btStateChangeWindowStart = Date()
        }
        if btStateChangeCount >= btStabilityThreshold {
            logActivity(.bluetooth, "BT unstable - \(btStateChangeCount) state changes in \(Int(btStabilityWindow))s window")
        }

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
        logActivity(.bluetooth, "State changed: \(stateName)")

        // Handle power on - set recovery cooldown and reset proximity states
        if central.state == .poweredOn {
            recoveryCooldown.start(at: Date())
            logActivity(.bluetooth, "BT recovery cooldown started (\(Int(RecoveryCooldown.duration))s)")
            for id in tracking.keys {
                tracking[id]?.proximity.assumeNearbyForRecovery()
            }
            startScanningIfNeeded()
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSINumber: NSNumber
    ) {
        guard let device = device(peripheral.identifier), !device.isClassicBluetooth else { return }

        if connectedPeripherals[device.id] == nil {
            logActivity(.bluetooth, "Connecting to BLE device: \(device.name)")
            peripheral.delegate = self
            connectedPeripherals[device.id] = peripheral
            centralManager.connect(peripheral, options: nil)
        }

        // 127 = RSSI unavailable: no reading, not a strong one
        if let rssi = RSSI(RSSINumber.intValue) {
            observe(.signal(rssi), for: peripheral.identifier, at: Date())
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard let deviceID = device(peripheral.identifier)?.id else { return }
        connectedPeripherals[deviceID] = peripheral
        peripheral.readRSSI()
        logActivity(.bluetooth, "Connected to: \(peripheral.name ?? "Unknown")")

        // All BLE trusted devices connected: stop BLE scanning to save CPU
        let bleDevices = trustedDevices.filter { !$0.isClassicBluetooth }
        if !bleDevices.isEmpty && bleDevices.allSatisfy({ connectedPeripherals[$0.id]?.state == .connected }) {
            centralManager.stopScan()
            logActivity(.bluetooth, "All BLE devices connected - stopped BLE scanning")
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard let deviceID = device(peripheral.identifier)?.id else { return }

        logActivity(.bluetooth, "Disconnected: \(peripheral.name ?? "Unknown")")
        connectedPeripherals.removeValue(forKey: deviceID)
        tracking[deviceID, default: DeviceTracking()].proximity.markDisconnected()

        if isScanning {
            scanForBLE()
            centralManager.connect(peripheral, options: nil)
            logActivity(.bluetooth, "Attempting reconnect to: \(peripheral.name ?? "Unknown")")
        }

        if areAllDevicesAway {
            onInput(.allTrustedDevicesAway)
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        logActivity(.bluetooth, "Failed to connect: \(error?.localizedDescription ?? "unknown")")
    }
}

// MARK: - CBPeripheralDelegate

extension BluetoothProximityManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSINumber: NSNumber, error: Error?) {
        if let error {
            logActivity(.bluetooth, "RSSI read error: \(error.localizedDescription)")
            return
        }
        // 127 = RSSI unavailable: no reading, not a strong one
        if let rssi = RSSI(RSSINumber.intValue) {
            observe(.signal(rssi), for: peripheral.identifier, at: Date())
        }
    }
}

// MARK: - IOBluetoothDeviceInquiryDelegate

extension BluetoothProximityManager: IOBluetoothDeviceInquiryDelegate {
    /// Device discovered during inquiry - provides fresh RSSI
    func deviceInquiryDeviceFound(_ sender: IOBluetoothDeviceInquiry!, device: IOBluetoothDevice!) {
        guard let address = device.addressString.flatMap(BluetoothAddress.init),
              let rssi = RSSI(Int(device.rawRSSI())) else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self,
                  let trustedDevice = self.trustedDevices.first(where: { $0.classicAddress == address }) else { return }

            let now = Date()
            self.tracking[trustedDevice.id, default: DeviceTracking()].classicLink.noteSignal(at: now)
            self.observe(.signal(rssi), for: trustedDevice.id, at: now)
            logActivity(.bluetooth, "Inquiry RSSI for \(trustedDevice.name): \(rssi)")
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
