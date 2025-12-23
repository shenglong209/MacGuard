---
title: "Support Multiple Trusted Devices"
description: "Allow users to configure multiple Bluetooth devices for proximity-based auto-arm/disarm"
status: completed
priority: P2
effort: 6h
issue: null
branch: feat/dynamic-menubar-icon
tags: [feature, bluetooth, settings]
created: 2025-12-23
reviewed: 2025-12-23
---

# Multiple Trusted Devices Implementation Plan

## Overview

Enable MacGuard to recognize multiple trusted Bluetooth devices for proximity detection. Currently limited to single device - users with multiple devices (iPhone + Apple Watch) must choose one.

**Behavior:**
- **Disarm:** ANY trusted device nearby → auto-disarm
- **Arm:** ALL trusted devices away → auto-arm (after grace period)

## Current Architecture

### Data Model
```swift
// Models/TrustedDevice.swift
struct TrustedDevice: Identifiable, Codable, Hashable {
    let id: UUID           // Bluetooth peripheral UUID
    var name: String       // Display name
    var lastRSSI: Int?     // Runtime only
    var lastSeen: Date?    // Runtime only
}
```

### Storage
- Key: `MacGuard.trustedDevice`
- Format: Single JSON-encoded TrustedDevice
- Location: UserDefaults

### BluetoothProximityManager
- `trustedDevice: TrustedDevice?` - single device
- `connectedPeripheral: CBPeripheral?` - single connection
- `isDeviceNearby: Bool` - binary state
- 1-second RSSI polling timer for connected device

### Limitations
1. Single device storage
2. Single peripheral connection
3. Binary nearby state (no per-device tracking)
4. DeviceScannerView replaces device on selection

---

## Implementation Design

### Phase 1: Data Model & Storage

**Files to modify:**
- `/Users/shenglong/DATA/XProject/MacGuard/Models/TrustedDevice.swift`
- `/Users/shenglong/DATA/XProject/MacGuard/Managers/BluetoothProximityManager.swift`

**Changes:**

1. **TrustedDevice model** - No changes needed (already suitable for array)

2. **BluetoothProximityManager storage:**

```swift
// Change from:
private let trustedDeviceKey = "MacGuard.trustedDevice"
@Published private(set) var trustedDevice: TrustedDevice?

// To:
private let trustedDevicesKey = "MacGuard.trustedDevices"
private let legacyTrustedDeviceKey = "MacGuard.trustedDevice"  // Migration
@Published private(set) var trustedDevices: [TrustedDevice] = []
```

3. **Migration logic:**
```swift
private func loadTrustedDevices() {
    // Try new key first
    if let data = UserDefaults.standard.data(forKey: trustedDevicesKey),
       let devices = try? JSONDecoder().decode([TrustedDevice].self, from: data) {
        trustedDevices = devices
        return
    }

    // Migrate from legacy single device
    if let data = UserDefaults.standard.data(forKey: legacyTrustedDeviceKey),
       let device = try? JSONDecoder().decode(TrustedDevice.self, from: data) {
        trustedDevices = [device]
        saveTrustedDevices()
        UserDefaults.standard.removeObject(forKey: legacyTrustedDeviceKey)
        print("[Bluetooth] Migrated single device to array")
    }
}
```

4. **Device management methods:**
```swift
func addTrustedDevice(_ device: TrustedDevice) {
    guard !trustedDevices.contains(where: { $0.id == device.id }) else { return }
    trustedDevices.append(device)
    saveTrustedDevices()
}

func removeTrustedDevice(_ device: TrustedDevice) {
    trustedDevices.removeAll { $0.id == device.id }
    saveTrustedDevices()
    disconnectPeripheral(for: device)
}

func removeAllTrustedDevices() {
    trustedDevices.removeAll()
    saveTrustedDevices()
    disconnectAllPeripherals()
}
```

---

### Phase 2: Multi-Device Bluetooth Tracking

**Files to modify:**
- `/Users/shenglong/DATA/XProject/MacGuard/Managers/BluetoothProximityManager.swift`

**Key insight:** CoreBluetooth supports multiple concurrent peripheral connections. Limit to 4-5 devices for practical RSSI polling efficiency.

**Changes:**

1. **Connection tracking:**
```swift
// Change from:
private var connectedPeripheral: CBPeripheral?

// To:
private var connectedPeripherals: [UUID: CBPeripheral] = [:]  // deviceID → peripheral
private var deviceProximityStates: [UUID: Bool] = [:]  // deviceID → isNearby
```

2. **Computed proximity state:**
```swift
// ANY device nearby = nearby
var isDeviceNearby: Bool {
    deviceProximityStates.values.contains(true)
}

// ALL devices away = away (for auto-arm logic)
var areAllDevicesAway: Bool {
    guard !trustedDevices.isEmpty else { return false }
    return deviceProximityStates.values.allSatisfy { !$0 }
}
```

3. **Device discovery - connect to all trusted devices:**
```swift
func centralManager(_ central: CBCentralManager,
                    didDiscover peripheral: CBPeripheral,
                    advertisementData: [String: Any],
                    rssi RSSI: NSNumber) {
    // Check if this peripheral matches ANY trusted device
    guard let matchingDevice = trustedDevices.first(where: { $0.id == peripheral.identifier }) else {
        return
    }

    // Connect if not already connected
    if connectedPeripherals[matchingDevice.id] == nil {
        print("[Bluetooth] Connecting to: \(matchingDevice.name)")
        connectedPeripherals[matchingDevice.id] = peripheral
        centralManager?.connect(peripheral, options: nil)
    }
}
```

4. **RSSI polling for all connected devices:**
```swift
@objc private func pollRSSI() {
    for (deviceID, peripheral) in connectedPeripherals {
        if peripheral.state == .connected {
            peripheral.readRSSI()
        } else {
            // Device disconnected - mark as away
            updateProximityState(for: deviceID, rssi: -100)
        }
    }
}
```

5. **Per-device RSSI handling with hysteresis:**
```swift
func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
    guard let deviceID = trustedDevices.first(where: { $0.id == peripheral.identifier })?.id else {
        return
    }

    updateProximityState(for: deviceID, rssi: RSSI.intValue)
}

private func updateProximityState(for deviceID: UUID, rssi: Int) {
    let wasNearby = isDeviceNearby
    let currentState = deviceProximityStates[deviceID] ?? false

    // Hysteresis logic (same as before, per device)
    let newState: Bool
    if currentState {
        newState = rssi >= rssiAwayThreshold  // Stay nearby unless below away threshold
    } else {
        newState = rssi >= rssiPresentThreshold  // Become nearby only above present threshold
    }

    deviceProximityStates[deviceID] = newState

    // Update runtime data on device
    if let index = trustedDevices.firstIndex(where: { $0.id == deviceID }) {
        trustedDevices[index].lastRSSI = rssi
        trustedDevices[index].lastSeen = Date()
    }

    // Notify delegate on state change
    let isNowNearby = isDeviceNearby
    if wasNearby != isNowNearby {
        if isNowNearby {
            if let device = trustedDevices.first(where: { $0.id == deviceID }) {
                delegate?.trustedDeviceNearby(device)
            }
        } else if areAllDevicesAway {
            delegate?.allTrustedDevicesAway()
        }
    }
}
```

6. **Handle disconnection:**
```swift
func centralManager(_ central: CBCentralManager,
                    didDisconnectPeripheral peripheral: CBPeripheral,
                    error: Error?) {
    guard let deviceID = trustedDevices.first(where: { $0.id == peripheral.identifier })?.id else {
        return
    }

    print("[Bluetooth] Disconnected: \(peripheral.name ?? "Unknown")")
    connectedPeripherals.removeValue(forKey: deviceID)
    deviceProximityStates[deviceID] = false

    // Reconnect if still trusted
    if trustedDevices.contains(where: { $0.id == deviceID }) {
        centralManager?.connect(peripheral, options: nil)
    }

    // Check if all devices now away
    if areAllDevicesAway && !trustedDevices.isEmpty {
        delegate?.allTrustedDevicesAway()
    }
}
```

---

### Phase 3: Delegate Protocol Updates

**Files to modify:**
- `/Users/shenglong/DATA/XProject/MacGuard/Managers/BluetoothProximityManager.swift`
- `/Users/shenglong/DATA/XProject/MacGuard/Managers/AlarmStateManager.swift`

**Changes:**

1. **Update protocol:**
```swift
protocol BluetoothProximityDelegate: AnyObject {
    func trustedDeviceNearby(_ device: TrustedDevice)      // ANY device came nearby
    func trustedDeviceAway(_ device: TrustedDevice)        // Specific device went away
    func allTrustedDevicesAway()                           // ALL devices now away
}
```

2. **AlarmStateManager handling:**
```swift
extension AlarmStateManager: BluetoothProximityDelegate {
    func trustedDeviceNearby(_ device: TrustedDevice) {
        // Auto-disarm immediately (any trusted device = owner present)
        if AppSettings.shared.autoDisarmOnDeviceArrive && state == .armed {
            print("[MacGuard:Bluetooth] \(device.name) nearby - auto-disarming")
            disarm()
        }
    }

    func trustedDeviceAway(_ device: TrustedDevice) {
        // Log but don't arm yet - wait for allTrustedDevicesAway
        print("[MacGuard:Bluetooth] \(device.name) went away")
    }

    func allTrustedDevicesAway() {
        // Auto-arm after grace period (all devices away = owner left)
        guard AppSettings.shared.autoArmOnDeviceLeave && state == .idle else { return }
        guard AppSettings.shared.autoArmMode == .allDevicesAway else { return }
        print("[MacGuard:Bluetooth] All devices away - starting grace period")
        startAutoArmGracePeriod()
    }

    func trustedDeviceAway(_ device: TrustedDevice) {
        // For "any device away" mode
        guard AppSettings.shared.autoArmOnDeviceLeave && state == .idle else { return }
        guard AppSettings.shared.autoArmMode == .anyDeviceAway else { return }
        print("[MacGuard:Bluetooth] \(device.name) away - starting grace period")
        startAutoArmGracePeriod()
    }
}
```

---

### Phase 4: Settings UI Updates

**Files to modify:**
- `/Users/shenglong/DATA/XProject/MacGuard/Views/SettingsView.swift`
- `/Users/shenglong/DATA/XProject/MacGuard/Views/DeviceScannerView.swift`

**SettingsView changes:**

1. **Device list section:**
```swift
// Section header with device count
Section {
    if alarmManager.bluetoothManager.trustedDevices.isEmpty {
        Text("No trusted devices configured")
            .foregroundColor(.secondary)
    } else {
        ForEach(alarmManager.bluetoothManager.trustedDevices) { device in
            trustedDeviceRow(device)
        }
        .onDelete { indexSet in
            for index in indexSet {
                let device = alarmManager.bluetoothManager.trustedDevices[index]
                alarmManager.bluetoothManager.removeTrustedDevice(device)
            }
        }
    }

    Button {
        showDeviceScanner = true
    } label: {
        Label("Add Device", systemImage: "plus.circle")
    }
} header: {
    HStack {
        Text("Trusted Devices")
        if !alarmManager.bluetoothManager.trustedDevices.isEmpty {
            Text("(\(alarmManager.bluetoothManager.trustedDevices.count))")
                .foregroundColor(.secondary)
        }
    }
}
```

2. **Per-device row (reuse existing trustedDeviceRow):**
- Show device icon, name, RSSI, nearby status
- Add swipe-to-delete

**DeviceScannerView changes:**

1. **Change selection behavior:**
```swift
// Change from replacing device:
private func selectDevice(_ device: TrustedDevice) {
    UserDefaults.standard.set(try? JSONEncoder().encode(device), forKey: "MacGuard.trustedDevice")
}

// To adding device:
private func selectDevice(_ device: TrustedDevice) {
    bluetoothManager.addTrustedDevice(device)
    dismiss()
}
```

2. **Filter already-added devices:**
```swift
var availableDevices: [BluetoothDevice] {
    pairedDevices.filter { paired in
        !bluetoothManager.trustedDevices.contains { $0.id == paired.identifier }
    }
}
```

3. **Show "already added" badge:**
```swift
if bluetoothManager.trustedDevices.contains(where: { $0.id == device.identifier }) {
    Text("Added")
        .font(.caption)
        .foregroundColor(.green)
}
```

---

### Phase 5: Edge Cases & Polish

**Considerations:**

1. **Device limit (10 max):**
```swift
private let maxTrustedDevices = 10

func addTrustedDevice(_ device: TrustedDevice) -> Bool {
    guard trustedDevices.count < maxTrustedDevices else {
        print("[Bluetooth] Max devices reached (\(maxTrustedDevices))")
        return false
    }
    // ... add device
    return true
}
```

2. **Auto-arm mode setting:**
```swift
// AppSettings.swift
enum AutoArmMode: String, Codable, CaseIterable {
    case allDevicesAway = "all"   // Arm when ALL devices leave
    case anyDeviceAway = "any"    // Arm when ANY device leaves
}
@AppStorage("autoArmMode") var autoArmMode: AutoArmMode = .allDevicesAway
```

3. **Disable "Add Device" when max reached:**
```swift
Button {
    showDeviceScanner = true
} label: {
    Label("Add Device", systemImage: "plus.circle")
}
.disabled(alarmManager.bluetoothManager.trustedDevices.count >= 10)
.help(alarmManager.bluetoothManager.trustedDevices.count >= 10
      ? "Maximum 10 devices allowed" : "")
```

4. **Empty state handling:**
- No devices → disable auto-arm/disarm toggles
- Show helpful text: "Add a device to enable proximity features"

5. **Connection status per device:**
- Show "Connected" / "Disconnected" / "Searching" status
- Helps users understand why auto-arm might not work

---

## File Changes Summary

| File | Action | Description |
|------|--------|-------------|
| `Managers/BluetoothProximityManager.swift` | Modify | Array storage, multi-connection, per-device RSSI |
| `Managers/AlarmStateManager.swift` | Modify | Handle new delegate methods |
| `Managers/AppSettings.swift` | Modify | Add `AutoArmMode` enum and setting |
| `Views/SettingsView.swift` | Modify | Device list UI, add/remove, auto-arm mode picker |
| `Views/DeviceScannerView.swift` | Modify | Add mode (don't replace) |

---

## Testing Plan

1. **Migration:**
   - [ ] Existing single device migrates to array on launch
   - [ ] Legacy key removed after migration
   - [ ] Fresh install works with empty array

2. **Multi-device:**
   - [ ] Can add up to 5 devices
   - [ ] Each device shows RSSI independently
   - [ ] Removing device disconnects it

3. **Proximity logic:**
   - [ ] ANY device nearby → `isDeviceNearby = true`
   - [ ] ALL devices away → auto-arm triggers
   - [ ] One device away, one nearby → stays disarmed

4. **UI:**
   - [ ] Device list shows all devices with status
   - [ ] Swipe to delete works
   - [ ] Add button opens scanner
   - [ ] Already-added devices hidden in scanner

---

## Resolved Decisions

| Question | Decision |
|----------|----------|
| Auto-arm mode | User toggle: all devices away vs any device away |
| Device limit | 10 max |
| Device rename | Defer - use Bluetooth name only |
| Max reached UX | Disable button + tooltip |

## Unresolved Questions

1. **Per-device thresholds?** - Same RSSI thresholds for all or per-device customization? (Recommend: defer, use global setting)

---

## Implementation Status

| Phase | Description | Status | Completed |
|-------|-------------|--------|-----------|
| 1 | Data Model & Storage | ✅ DONE | 2024-12-24 |
| 2 | Multi-Device Bluetooth Tracking | ✅ DONE | 2024-12-24 |
| 3 | Delegate Protocol Updates | ✅ DONE | 2024-12-24 |
| 4 | Settings UI Updates | ✅ DONE | 2024-12-24 |
| 5 | Edge Cases & Polish | 📋 Deferred | - |

---

## Implementation Order

1. **Phase 1** - Data model & storage migration (foundation) - ✅ DONE (2024-12-24)
2. **Phase 2** - Multi-device Bluetooth tracking (core logic) - ✅ DONE (2024-12-24)
3. **Phase 3** - Delegate protocol updates (integration) - ✅ DONE (2024-12-24)
4. **Phase 4** - Settings UI updates (user-facing) - ✅ DONE (2024-12-24)
5. **Phase 5** - Edge cases & polish (refinement) - 📋 Planned (deferred)

MVP complete. Phase 5 deferred to future iteration.
