# CPU Optimization Plan: 10% → <2%

**Date:** 2025-12-23
**Target:** Reduce idle/armed CPU from ~10% to <2%
**Risk Level:** Medium (touches core monitoring logic)

## Problem Summary

MacGuard consumes ~10% CPU due to aggressive polling and inefficient Bluetooth scanning:

| Issue | Location | Impact |
|-------|----------|--------|
| `allowDuplicates: true` | BluetoothProximityManager:123 | Processes every BLE packet (~10-20/sec/device) |
| `withServices: nil` | BluetoothProximityManager:123 | Scans ALL nearby BLE devices |
| Unconditional scanning | AlarmStateManager:183 | Scans even when auto-arm OFF (default) |
| 0.5s lid polling | SleepMonitor:84 | Aggressive IOKit syscalls |

## Features That MUST Continue Working

| Feature | When Active | Mechanism |
|---------|-------------|-----------|
| Auto-disarm when trusted device nearby | Armed state | RSSI > presentThreshold |
| Auto-arm when device leaves | Idle + setting ON | RSSI < awayThreshold → timer |
| UI shows device connection status | Settings open | Visual feedback |
| Bluetooth proximity checks | Armed state | Block trigger if device nearby |

## Solution Design

### Phase 1: Conditional Bluetooth Scanning

**Current behavior:**
```swift
// AlarmStateManager.swift:183
func disarm() {
    // ... stop everything ...
    bluetoothManager.startScanning()  // ALWAYS runs
}
```

**New behavior:**
```swift
func disarm() {
    // ... stop everything ...
    // Only scan if auto-arm enabled AND trusted device exists
    if AppSettings.shared.autoArmOnDeviceLeave,
       bluetoothManager.trustedDevice != nil {
        bluetoothManager.startScanning()
    }
}
```

**Files:** `AlarmStateManager.swift`

### Phase 2: Optimize Bluetooth Scanning Method

**Current behavior:**
```swift
// BluetoothProximityManager.swift:122-126
centralManager.scanForPeripherals(
    withServices: nil,  // ALL devices
    options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]  // EVERY packet
)
```

**New behavior:**
```swift
centralManager.scanForPeripherals(
    withServices: nil,  // Keep nil (trusted device may not advertise services)
    options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]  // One per device
)
```

**Rationale:**
- `allowDuplicates: false` = one discovery callback per device
- RSSI updates come from `readRSSI()` on connected peripheral (already 1.0s timer at line 129)
- Once connected, discovery callbacks are redundant

**Additional optimization - stop scanning once connected:**
```swift
func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    connectedPeripheral = peripheral
    peripheral.readRSSI()

    // Stop scanning - rely on connected RSSI readings
    if isScanning {
        centralManager.stopScan()
    }
}
```

**Files:** `BluetoothProximityManager.swift`

### Phase 3: Increase Lid Polling Interval

**Current behavior:**
```swift
// SleepMonitor.swift:84
lidStateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true)
```

**New behavior:**
```swift
lidStateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true)
```

**Rationale:**
- Lid close is not time-critical (user physically closing laptop)
- 1.0s detection is still responsive enough
- Halves IOKit syscall frequency

**Files:** `SleepMonitor.swift`

---

## Implementation Tasks

### Task 1: BluetoothProximityManager Optimization

**File:** `Managers/BluetoothProximityManager.swift`

**Changes:**

1. **Line 123-126:** Change `allowDuplicates` to `false`
```swift
// BEFORE
centralManager.scanForPeripherals(
    withServices: nil,
    options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
)

// AFTER
centralManager.scanForPeripherals(
    withServices: nil,
    options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
)
```

2. **Line 238-242 (`didConnect`):** Stop scanning after connection
```swift
func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    connectedPeripheral = peripheral
    peripheral.readRSSI()
    print("[Bluetooth] Connected to trusted device")

    // ADD: Stop peripheral scanning - rely on connected RSSI readings
    if isScanning {
        centralManager.stopScan()
        print("[Bluetooth] Stopped scanning (connected)")
    }
}
```

3. **Line 244-252 (`didDisconnect`):** Resume scanning on disconnect
```swift
func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
    connectedPeripheral = nil
    print("[Bluetooth] Disconnected from trusted device")

    // Reconnect if still trusted and scanning
    if isScanning, let device = trustedDevice, device.id == peripheral.identifier {
        // ADD: Resume scanning to rediscover device
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        centralManager.connect(peripheral, options: nil)
    }
}
```

---

### Task 2: AlarmStateManager Conditional Scanning

**File:** `Managers/AlarmStateManager.swift`

**Changes:**

1. **Line 183 (in `disarm()`):** Conditional scanning
```swift
// BEFORE
func disarm() {
    // ... existing code ...

    // Restart background scanning for UI display
    bluetoothManager.startScanning()
}

// AFTER
func disarm() {
    // ... existing code ...

    // Only scan in idle if auto-arm enabled AND trusted device configured
    if AppSettings.shared.autoArmOnDeviceLeave,
       bluetoothManager.trustedDevice != nil {
        bluetoothManager.startScanning()
    }
}
```

2. **Add method to handle setting changes** (new method after line 301):
```swift
/// Called when autoArmOnDeviceLeave setting changes
func handleAutoArmSettingChanged(_ enabled: Bool) {
    if state == .idle {
        if enabled, bluetoothManager.trustedDevice != nil {
            bluetoothManager.startScanning()
        } else {
            bluetoothManager.stopScanning()
        }
    }
}
```

3. **Subscribe to setting changes in `init()`** (add after line 57):
```swift
// Observe autoArmOnDeviceLeave changes
AppSettings.shared.$autoArmOnDeviceLeave
    .receive(on: RunLoop.main)
    .sink { [weak self] enabled in
        self?.handleAutoArmSettingChanged(enabled)
    }
    .store(in: &cancellables)
```

**Note:** Requires adding `@Published` wrapper to `autoArmOnDeviceLeave` in `AppSettings.swift` OR using `objectWillChange` publisher.

---

### Task 3: AppSettings Publisher for autoArmOnDeviceLeave

**File:** `Models/AppSettings.swift`

**Option A - Use Combine publisher (Recommended):**

Add after line 106:
```swift
/// Publisher for autoArmOnDeviceLeave changes
var autoArmOnDeviceLeavePublisher: AnyPublisher<Bool, Never> {
    UserDefaults.standard.publisher(for: \.autoArmOnDeviceLeave)
        .eraseToAnyPublisher()
}
```

Then update AlarmStateManager to use:
```swift
AppSettings.shared.autoArmOnDeviceLeavePublisher
    .sink { [weak self] enabled in
        self?.handleAutoArmSettingChanged(enabled)
    }
    .store(in: &cancellables)
```

**Option B - Simple approach (observe objectWillChange):**

Since AppSettings already sends `objectWillChange`, AlarmStateManager can observe that. But this fires for ALL settings changes, so less efficient.

**Recommendation:** Option A for targeted observation.

---

### Task 4: SleepMonitor Polling Interval

**File:** `Managers/SleepMonitor.swift`

**Changes:**

1. **Line 84:** Increase interval from 0.5s to 1.0s
```swift
// BEFORE
lidStateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true)

// AFTER
lidStateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true)
```

---

## State Transition Matrix (Verification)

| Current State | Event | Auto-arm Setting | Expected Scanning |
|---------------|-------|------------------|-------------------|
| Idle | App launch | OFF | **NO scanning** |
| Idle | App launch | ON + trusted device | YES scanning |
| Idle | User enables auto-arm | - | Start scanning |
| Idle | User disables auto-arm | - | Stop scanning |
| Idle → Armed | arm() | Any | YES scanning |
| Armed → Idle | disarm() | OFF | **NO scanning** |
| Armed → Idle | disarm() | ON | YES scanning |

---

## Testing Checklist

### Functionality Tests

- [ ] **Auto-disarm when armed:** Trusted device comes in range → disarms
- [ ] **Auto-arm when device leaves:** Idle + setting ON → device leaves → timer → arms
- [ ] **Trigger blocked by proximity:** Armed + trusted nearby → input detected → NO trigger
- [ ] **Manual arm/disarm:** Works regardless of Bluetooth
- [ ] **No trusted device:** App works without Bluetooth features

### CPU Verification

- [ ] **Idle (no auto-arm):** CPU < 1%
- [ ] **Idle (auto-arm ON):** CPU < 2%
- [ ] **Armed state:** CPU < 3%
- [ ] **Alarming state:** CPU acceptable (audio playing)

### Edge Cases

- [ ] **Setting toggle while idle:** Scanning starts/stops correctly
- [ ] **Bluetooth off/on:** Scanning resumes correctly
- [ ] **Trusted device removed:** Scanning stops
- [ ] **Device disconnect/reconnect:** Scanning resumes, connects again

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Auto-arm feature breaks | Medium | High | Thorough testing with real device |
| RSSI readings less frequent | Low | Low | Connected RSSI timer (1.0s) still active |
| Lid detection slower | Low | Low | 1.0s still responsive for physical action |
| Bluetooth reconnect fails | Low | Medium | Keep reconnect logic in didDisconnect |

---

## Rollback Plan

If issues discovered:
1. Revert `allowDuplicates` to `true`
2. Revert lid polling to `0.5s`
3. Revert conditional scanning (always scan)

All changes are isolated and easily reversible.

---

## Files Modified Summary

| File | Changes |
|------|---------|
| `Managers/BluetoothProximityManager.swift` | `allowDuplicates: false`, stop scan on connect |
| `Managers/AlarmStateManager.swift` | Conditional scanning in disarm(), setting observer |
| `Managers/SleepMonitor.swift` | Polling interval 0.5s → 1.0s |
| `Models/AppSettings.swift` | Add publisher for setting changes (optional) |

**Total LOC changed:** ~30 lines
**Estimated effort:** Low-Medium
