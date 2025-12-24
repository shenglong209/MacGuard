# AirPods BLE Detection Issue - Diagnostic Report

**Date:** 2024-12-24
**Issue:** AirPods cannot be scanned or detected for proximity in MacGuard
**Severity:** Medium (affects subset of users w/ AirPods as trusted device)

---

## Executive Summary

**Root Cause:** AirPods use **Classic Bluetooth (BR/EDR)** for audio streaming, not BLE advertising. CoreBluetooth's `CBCentralManager.scanForPeripherals()` only detects **BLE peripherals**, not Classic Bluetooth devices. AirPods do have BLE capability (for pairing/switching), but Apple's H1/H2 chips limit BLE advertisement visibility to 3rd-party apps.

**Impact:**
- AirPods visible in IOBluetooth paired devices list
- AirPods NOT discoverable via CBCentralManager BLE scan
- Even if manually added, `peripheral.readRSSI()` fails (no BLE connection)

---

## Technical Analysis

### 1. Current Implementation

**DeviceScannerView.swift (lines 86-105):**
```swift
// Uses IOBluetooth for paired device names
let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]

// Uses CoreBluetooth for BLE discovery + RSSI
central.scanForPeripherals(withServices: nil, options: [...])
```

**BluetoothProximityManager.swift (lines 191-204):**
```swift
centralManager.scanForPeripherals(withServices: nil, options: [...])
// RSSI via connected peripheral's readRSSI()
```

**Problem:** Two-step approach:
1. Get paired device *names* from IOBluetooth (works for AirPods)
2. Match names to BLE peripherals (FAILS for AirPods - no BLE advertisement)

### 2. Why AirPods Fail

| Aspect | AirPods Behavior | MacGuard Requirement |
|--------|------------------|---------------------|
| Bluetooth Type | Classic BR/EDR (audio) | BLE (CBCentralManager) |
| BLE Advertising | Minimal/proprietary | Open advertisement |
| UUID Consistency | Changes per connection | Stable UUID matching |
| RSSI Access | Only via IOBluetooth | via CBPeripheral.readRSSI() |

**Key Issue:** AirPods BLE UUID from CBCentralManager != AirPods Classic UUID from IOBluetooth. Even if pairing names match, UUIDs differ.

### 3. Evidence from Code

**DeviceScannerView.swift lines 163-169:**
```swift
// Check if device is paired (case-insensitive exact match)
let isPaired = pairedDeviceNames.contains { pairedName in
    name.localizedCaseInsensitiveCompare(pairedName) == .orderedSame
}
guard isPaired else { return }  // AirPods never reach here
```

AirPods never appear in `didDiscover` callback because they don't advertise over BLE.

---

## Potential Solutions

### Option A: IOBluetooth RSSI (Classic Bluetooth)

**Approach:** Use `IOBluetoothDevice.rawRSSI()` for Classic Bluetooth RSSI.

**Pros:**
- Works with Classic Bluetooth devices (AirPods, older headphones)
- Direct access to connected device signal strength

**Cons:**
- IOBluetooth is legacy framework, deprecated API warnings
- `rawRSSI()` requires active Classic Bluetooth connection (audio playing)
- Less reliable polling than BLE
- May require entitlements/permissions

**Implementation:**
```swift
import IOBluetooth

func pollClassicBluetoothRSSI() {
    guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return }
    for device in paired {
        if device.isConnected() {
            let rssi = device.rawRSSI()  // Returns BluetoothHCIRSSIValue
            print("[\(device.name ?? "?")] RSSI: \(rssi)")
        }
    }
}
```

### Option B: Connection-Based Proximity

**Approach:** Instead of RSSI, detect AirPods as "nearby" when connected, "away" when disconnected.

**Pros:**
- Simple, reliable
- Works with all Bluetooth device types

**Cons:**
- Binary (connected/disconnected), no distance detection
- User must keep AirPods connected (in ears or case open)
- AirPods disconnect when in closed case

**Implementation:**
```swift
func isAirPodsNearby() -> Bool {
    guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return false }
    return paired.contains {
        $0.name?.lowercased().contains("airpods") == true && $0.isConnected()
    }
}
```

### Option C: Hybrid Approach (Recommended)

**Approach:** Use BLE for devices that support it, fall back to IOBluetooth for Classic-only devices.

**Implementation:**
1. Add `deviceType` field to TrustedDevice: `.ble` or `.classic`
2. Scanner tries BLE first; if device only appears in IOBluetooth.pairedDevices(), mark as `.classic`
3. BluetoothProximityManager uses different polling strategies:
   - `.ble`: CBPeripheral.readRSSI()
   - `.classic`: IOBluetoothDevice.rawRSSI() or isConnected()

**Pros:**
- Best of both worlds
- Graceful fallback
- User transparency

**Cons:**
- More complex codebase
- Two monitoring paths to maintain

### Option D: Document Limitation

**Approach:** Add help text explaining AirPods limitation.

**Minimum effort solution:**
- In DeviceScannerView empty state, add note: "AirPods and some audio devices use Classic Bluetooth and may not appear. Use iPhone or Apple Watch instead."

---

## Recommendations

1. **Short-term (v1.3.x):** Option D - Document limitation
   - Lowest risk, immediate user clarity
   - Add warning in Settings when AirPods added but never connects

2. **Medium-term (v1.4.x):** Option B + C hybrid
   - Implement IOBluetooth connection-based detection
   - Mark device type during scan/add process
   - Use connection status for Classic devices

3. **Long-term:** Monitor Apple's BLE changes
   - Apple may expose more AirPods BLE data in future macOS
   - New Accessory Setup Kit may provide alternative

---

## Files Affected

| File | Current Role | Changes Needed |
|------|--------------|----------------|
| `Managers/BluetoothProximityManager.swift` | BLE-only proximity | Add IOBluetooth fallback |
| `Views/DeviceScannerView.swift` | BLE discovery + IOBluetooth names | Direct IOBluetooth scan option |
| `Models/TrustedDevice.swift` | Generic device | Add `deviceType` enum |

---

## Unresolved Questions

1. Does `IOBluetoothDevice.rawRSSI()` work reliably on modern macOS (Sonoma/Sequoia)?
2. Does IOBluetooth require additional entitlements or user permissions?
3. How frequently does AirPods Classic RSSI update when in use?
4. Should we poll IOBluetooth periodically or use KVO/notifications for connection changes?
