# Code Review: Classic BT Detection Improvements

**Date**: 2025-12-24
**Files**: BluetoothProximityManager.swift, AlarmStateManager.swift
**Scope**: IOBluetoothDeviceInquiry, RSSI fallback, armed polling optimization

## Overall Assessment

Code is well-structured with proper memory management. No critical security vulnerabilities. Minor improvements recommended.

## Critical Issues

None.

## High Priority Findings

### 1. Thread Safety - IOBluetoothDeviceInquiry Delegate

**File**: BluetoothProximityManager.swift:650-686

IOBluetoothDeviceInquiry callbacks may occur on background threads, but `trustedDevices` array and dictionaries are accessed without synchronization.

```swift
func deviceInquiryDeviceFound(_ sender: IOBluetoothDeviceInquiry!, device: IOBluetoothDevice!) {
    // Accesses trustedDevices, classicDeviceLastValidRSSI without main thread dispatch
    guard let trustedDevice = trustedDevices.first(where: { ... }) else { return }
    classicDeviceLastValidRSSI[trustedDevice.id] = Date()
    updateProximityState(for: trustedDevice.id, rssi: Int(rssi))
}
```

**Recommendation**: Wrap in `DispatchQueue.main.async { }` or mark BluetoothProximityManager as `@MainActor`.

### 2. Timer Not on Main Thread Guarantee

**File**: BluetoothProximityManager.swift:114, 277

Timer callbacks may mutate state. CBCentralManager initialized with `queue: nil` uses main queue, but IOBluetooth callbacks don't.

**Impact**: Low - current usage appears safe since CBCentralManager runs on main.

## Medium Priority Improvements

### 1. deviceInquiry Not Stopped in All Paths

**File**: BluetoothProximityManager.swift:291-292

`stopScanning()` calls `deviceInquiry?.stop()` - good. But `removeAllTrustedDevices()` and related methods don't stop inquiry if no classic devices remain.

**Recommendation**: Add check in device removal to stop inquiry when no classic devices left.

### 2. Repeated Date() Allocations

**File**: BluetoothProximityManager.swift:400, 404-405

```swift
classicDeviceLastValidRSSI[device.id] = Date()
// ...
let lastValid = classicDeviceLastValidRSSI[device.id] ?? .distantPast
if Date().timeIntervalSince(lastValid) > rssiUnavailableTimeout { ... }
```

**Impact**: Negligible - Date() is lightweight.

### 3. Magic Number -50 for Fallback RSSI

**File**: BluetoothProximityManager.swift:359, 387, 407

Hardcoded `-50` as "assumed nearby" RSSI used in 3 places.

**Recommendation**: Extract to named constant `private let fallbackNearbyRSSI = -50`.

## Low Priority Suggestions

1. **inquiryLength = 5** could be configurable for power-sensitive scenarios
2. **rssiUnavailableTimeout = 1.0s** is aggressive - consider 2-3s for flaky devices

## Positive Observations

- Proper `[weak self]` in all Timer closures prevents retain cycles
- Clean hysteresis logic with separate present/away thresholds
- Proper cleanup in `removeTrustedDevice` - all tracking dicts cleared
- `setArmedState` guards against redundant calls
- Build passes with no warnings

## Security Review

- No hardcoded secrets
- No user input directly passed to shell/AppleScript in new code
- IOBluetooth device matching by address is safe
- RSSI values properly validated (127, 0 = invalid)

## Architecture

- Integration between AlarmStateManager and BluetoothProximityManager is clean
- Armed state propagation via `setArmedState()` is appropriate
- Polling interval optimization (500ms armed, 1s idle) is sensible

## Recommended Actions

1. **[High]** Add main thread dispatch to IOBluetoothDeviceInquiryDelegate methods
2. **[Medium]** Extract fallback RSSI constant
3. **[Low]** Stop deviceInquiry when last classic device removed

## Metrics

- Build Status: PASS
- Compile Warnings: 0
- Lines Changed: ~130 additions
