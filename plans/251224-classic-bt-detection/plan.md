# Plan: Improve Classic Bluetooth Device Detection

**Created:** 2024-12-24
**Status:** Ready for Implementation
**Priority:** P0 (Critical UX bug)

## Problem Statement

When a Classic Bluetooth trusted device returns within Detection Distance, there's a 7-second delay before auto-disarm triggers. This causes false alarm activations even when the user is present with their trusted device.

### Root Cause

In `BluetoothProximityManager.swift` lines 347-353:

```swift
} else if isConnected {
    // Device still connected - update RSSI if available
    let rssi = ioDevice.rawRSSI()
    if rssi != 127 && rssi != 0 {
        updateProximityState(for: device.id, rssi: Int(rssi))
    }
    // BUG: When RSSI unavailable (127 or 0), NO UPDATE happens
    // Device stays in old "away" state indefinitely
}
```

**Technical details:**
- `IOBluetoothDevice.rawRSSI()` returns cached/stale values
- Values 127 or 0 indicate RSSI unavailable
- When unavailable, proximity state is NOT updated
- Device remains in "away" state even though it's physically nearby

### User Requirements (Exact)

1. Device leaves out of Detection Distance → auto-arm
2. Device returns within Detection Distance → auto-disarm **instantly**
3. Detection Distance setting is the SOURCE OF TRUTH, not connection state
4. Connected device at 10m should still be "away" if Detection Distance is "Near" (~1-2m)

## Solution Design

### Approach: IOBluetoothDeviceInquiry Active Scanning

Use `IOBluetoothDeviceInquiry` for active Bluetooth scanning which provides fresh RSSI values during discovery callbacks.

**Why this approach:**
- `rawRSSI()` on `IOBluetoothDevice` is cached and unreliable
- `IOBluetoothDeviceInquiry` actively probes devices and provides real-time RSSI
- Already imported `IOBluetooth` framework
- Works for Classic Bluetooth devices (non-BLE)

### Implementation Changes

#### Phase 1: Add IOBluetoothDeviceInquiry

**File:** `Managers/BluetoothProximityManager.swift`

1. Add `IOBluetoothDeviceInquiryDelegate` conformance
2. Create inquiry object and configure for continuous scanning
3. Implement delegate callbacks:
   - `deviceInquiryDeviceFound(_:device:)` - device discovered with RSSI
   - `deviceInquiryUpdatingDeviceNamesStarted(_:devicesRemaining:)`
   - `deviceInquiryComplete(_:error:aborted:)` - restart inquiry for continuous scanning

```swift
// Add to class
private var deviceInquiry: IOBluetoothDeviceInquiry?

// Configure inquiry
func setupDeviceInquiry() {
    deviceInquiry = IOBluetoothDeviceInquiry(delegate: self)
    deviceInquiry?.updateNewDeviceNames = false  // Skip name resolution for speed
    deviceInquiry?.inquiryLength = 5  // 5 second inquiry cycles
}

// IOBluetoothDeviceInquiryDelegate
func deviceInquiryDeviceFound(_ sender: IOBluetoothDeviceInquiry!, device: IOBluetoothDevice!) {
    // Check if this is a trusted Classic BT device
    guard let address = device.addressString,
          let trustedDevice = trustedDevices.first(where: {
              $0.isClassicBluetooth && $0.bluetoothAddress == address
          }) else { return }

    // Get fresh RSSI from inquiry result
    let rssi = device.rawRSSI()
    if rssi != 127 && rssi != 0 {
        updateProximityState(for: trustedDevice.id, rssi: Int(rssi))
    }
}

func deviceInquiryComplete(_ sender: IOBluetoothDeviceInquiry!, error: IOReturn, aborted: Bool) {
    // Restart inquiry for continuous monitoring
    if isScanning && !aborted {
        sender.start()
    }
}
```

#### Phase 2: Hybrid Approach with Fallback

When RSSI unavailable from both `rawRSSI()` and inquiry:

1. If device is CONNECTED and RSSI unavailable for >1 second:
   - Use estimated RSSI based on connection quality
   - Fallback to `-50` (strong signal) to trigger "nearby" check

2. Track "RSSI unavailable" duration per device:
   ```swift
   private var classicDeviceLastValidRSSI: [UUID: Date] = [:]
   private let rssiUnavailableTimeout: TimeInterval = 1.0
   ```

3. Modified logic in `pollClassicBluetoothDevices()`:
   ```swift
   } else if isConnected {
       let rssi = ioDevice.rawRSSI()
       if rssi != 127 && rssi != 0 {
           // Valid RSSI - update state and timestamp
           classicDeviceLastValidRSSI[device.id] = Date()
           updateProximityState(for: device.id, rssi: Int(rssi))
       } else {
           // RSSI unavailable - check timeout
           let lastValid = classicDeviceLastValidRSSI[device.id] ?? .distantPast
           if Date().timeIntervalSince(lastValid) > rssiUnavailableTimeout {
               // Timeout - use fallback RSSI for connected device
               updateProximityState(for: device.id, rssi: -50)
           }
       }
   }
   ```

#### Phase 3: Increase Polling Frequency When Armed

When alarm is armed and looking for trusted device:

```swift
private var isArmed = false
private let normalPollingInterval: TimeInterval = 1.0
private let armedPollingInterval: TimeInterval = 0.5  // 500ms when armed

func setArmedState(_ armed: Bool) {
    isArmed = armed
    if isScanning {
        // Restart timer with new interval
        rssiReadTimer?.invalidate()
        let interval = armed ? armedPollingInterval : normalPollingInterval
        rssiReadTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] in
            self?.pollAllDevices()
        }
    }
}
```

## Implementation Phases

### Phase 1: IOBluetoothDeviceInquiry Integration
**Files:** `BluetoothProximityManager.swift`
**LOC:** ~80 lines added

1. Add `IOBluetoothDeviceInquiryDelegate` conformance
2. Create and configure `IOBluetoothDeviceInquiry`
3. Implement delegate callbacks
4. Start/stop inquiry with scanning lifecycle
5. Test: Verify inquiry provides fresh RSSI for Classic BT devices

### Phase 2: RSSI Unavailable Fallback
**Files:** `BluetoothProximityManager.swift`
**LOC:** ~30 lines changed

1. Add `classicDeviceLastValidRSSI` tracking dictionary
2. Add `rssiUnavailableTimeout` constant (1.0 seconds)
3. Modify `pollClassicBluetoothDevices()` to handle RSSI unavailable with fallback
4. Test: Connect Classic BT device, verify fallback triggers after 1s

### Phase 3: Armed State Optimization
**Files:** `BluetoothProximityManager.swift`, `AlarmStateManager.swift`
**LOC:** ~20 lines

1. Add `setArmedState()` method to BluetoothProximityManager
2. Call from AlarmStateManager when state changes to armed
3. Increase polling frequency when armed (0.5s vs 1.0s)
4. Test: Verify faster detection when armed

## Testing Plan

### Manual Test Cases

1. **Basic Detection**
   - Connect Classic BT headphones
   - Arm MacGuard
   - Walk away until auto-arm triggers
   - Return within Detection Distance
   - **Expected:** Auto-disarm within 1-2 seconds

2. **RSSI Unavailable Scenario**
   - Connect Classic BT device that returns 127/0 RSSI
   - Arm MacGuard
   - Touch keyboard (trigger countdown)
   - **Expected:** Countdown cancelled within 3 seconds if device nearby

3. **Detection Distance Accuracy**
   - Set Detection Distance to "Near" (~1-2m)
   - Stand at 3m with connected Classic BT device
   - **Expected:** Device marked as "away" despite connection

### Edge Cases

- Device connected but RSSI never available → fallback after 3s
- Multiple Classic BT devices → all should be tracked
- Rapid connect/disconnect → debounce prevents oscillation
- Bluetooth disabled during scanning → graceful handling

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| IOBluetoothDeviceInquiry deprecated | Medium | Fallback to rawRSSI() + timeout approach |
| Inquiry drains battery | Low | 5-second cycles, stop when not armed |
| False "nearby" from fallback RSSI | Medium | Use conservative -50 dB (close range only) |
| Inquiry conflicts with audio | Low | Test with audio streaming, adjust if needed |

## Success Criteria

1. Auto-disarm latency < 2 seconds when Classic BT device returns
2. No false alarms when user is present with trusted device
3. Detection Distance setting respected for all device types
4. No regression in BLE device detection
5. Battery impact < 2% increase

## Dependencies

- IOBluetooth framework (already imported)
- No new external dependencies

## Estimated Effort

- Phase 1: 30 minutes (critical fix)
- Phase 2: 1 hour (inquiry integration)
- Phase 3: 30 minutes (optional optimization)
- Testing: 30 minutes

**Total:** ~2-3 hours

## Validation Summary

**Validated:** 2024-12-24 (Re-validated)
**Questions asked:** 4 + 4 (re-validation)

### Confirmed Decisions
- **Fallback RSSI value:** Use fixed -50 dB (conservative, near range only)
- **Phase ordering:** Phase 1 first (IOBluetoothDeviceInquiry), then fallback as backup
- **Timeout duration:** 1 second (faster response, user prefers speed)
- **Armed polling:** Yes, implement Phase 3 with 500ms polling when armed

### Re-validation Decisions (2024-12-24)
- **Unknown devices:** Filter early in callback - check address against trusted list immediately
- **Inquiry cycle:** 5 seconds, accept minor audio glitches
- **Fallback logic:** Connected=nearby ONLY if IOBluetoothDeviceInquiry fails to provide RSSI
- **Priority order:**
  1. Try IOBluetoothDeviceInquiry for fresh RSSI first
  2. If inquiry provides no RSSI AND device connected → assume nearby (-50 dB)
  3. If not connected AND no RSSI → device is away

### Action Items
- [x] Reorder phases: IOBluetoothDeviceInquiry first, fallback second
- [x] Change timeout from 3.0 to 1.0 seconds
- [x] Phase 3 is now required, not optional
- [ ] Update fallback logic: only use "connected=nearby" when inquiry fails
