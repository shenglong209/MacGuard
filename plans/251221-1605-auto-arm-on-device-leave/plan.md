---
title: "Auto-Arm When Trusted Device Leaves"
description: "Add feature to automatically arm MacGuard when configured trusted Bluetooth device leaves proximity"
status: pending
priority: P2
effort: 2h
issue:
branch: main
tags: [feature, bluetooth, settings]
created: 2025-12-21
---

# Auto-Arm When Trusted Device Leaves

## Overview

When a trusted Bluetooth device (iPhone/AirPods/Watch) is configured and leaves proximity, MacGuard auto-arms with configurable delay.

## Requirements (from user input)

1. **User toggle decides** - Add setting to control auto-arm behavior
2. **Configurable grace period** - Delay before arming (debounce)
3. **Follow existing lock setting** - Respect `autoLockOnArm` for screen lock

## Implementation Design

### 1. AppSettings Changes

Add two new `@AppStorage` properties:

```swift
@AppStorage("autoArmOnDeviceLeave") var autoArmOnDeviceLeave: Bool = false
@AppStorage("autoArmGracePeriod") var autoArmGracePeriod: Int = 15 // seconds (10-60 range)
```

### 2. AlarmStateManager Changes

Add timer-based auto-arm logic:

```swift
// New property
private var autoArmTimer: Timer?

// In trustedDeviceAway(_:)
func trustedDeviceAway(_ device: TrustedDevice) {
    Task { @MainActor in
        print("[MacGuard] Trusted device left proximity")

        guard AppSettings.shared.autoArmOnDeviceLeave,
              self.state == .idle else { return }

        self.startAutoArmTimer()
    }
}

// In trustedDeviceNearby(_:)
func trustedDeviceNearby(_ device: TrustedDevice) {
    Task { @MainActor in
        // Cancel pending auto-arm
        self.cancelAutoArmTimer()

        // Existing auto-disarm logic...
        if self.state == .triggered || self.state == .alarming {
            print("[MacGuard] Trusted device detected - auto-disarming")
            self.disarm()
        }
    }
}

private func startAutoArmTimer() {
    autoArmTimer?.invalidate()
    let delay = AppSettings.shared.autoArmGracePeriod
    print("[MacGuard] Starting auto-arm timer (\(delay)s)")

    autoArmTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(delay), repeats: false) { [weak self] _ in
        Task { @MainActor in
            guard let self = self, self.state == .idle else { return }
            print("[MacGuard] Auto-arming - trusted device still away")
            self.arm()
        }
    }
}

private func cancelAutoArmTimer() {
    if autoArmTimer != nil {
        print("[MacGuard] Cancelled auto-arm timer - device returned")
    }
    autoArmTimer?.invalidate()
    autoArmTimer = nil
}
```

### 3. SettingsView Changes

Add UI controls in "Trusted Device" section (after "Detection Distance" picker):

```swift
// Inside Section "Trusted Device", after existing device display
if alarmManager.bluetoothManager.trustedDevice != nil {
    // ... existing device row and detection distance picker ...

    Toggle("Auto-arm when device leaves", isOn: $settings.autoArmOnDeviceLeave)

    if settings.autoArmOnDeviceLeave {
        Picker("Grace period", selection: $settings.autoArmGracePeriod) {
            Text("10 seconds").tag(10)
            Text("15 seconds").tag(15)
            Text("30 seconds").tag(30)
            Text("60 seconds").tag(60)
        }
        .pickerStyle(.menu)
    }
}
```

## Files to Modify

| File | Action | Changes |
|------|--------|---------|
| `Models/AppSettings.swift` | Modify | Add 2 `@AppStorage` properties |
| `Managers/AlarmStateManager.swift` | Modify | Add timer, update delegate methods |
| `Views/SettingsView.swift` | Modify | Add Toggle + conditional Picker |

## Phase Breakdown

### Phase 1: Settings (10 min)

**File:** `Models/AppSettings.swift`

After line 104 (`proximityDistance`), add:

```swift
@AppStorage("autoArmOnDeviceLeave") var autoArmOnDeviceLeave: Bool = false
@AppStorage("autoArmGracePeriod") var autoArmGracePeriod: Int = 15
```

### Phase 2: State Manager Logic (20 min)

**File:** `Managers/AlarmStateManager.swift`

1. Add property after line 28 (`private var cancellables`):
   ```swift
   private var autoArmTimer: Timer?
   ```

2. Add helper methods before `// MARK: - InputMonitorDelegate`:
   ```swift
   private func startAutoArmTimer() { ... }
   private func cancelAutoArmTimer() { ... }
   ```

3. Update `trustedDeviceNearby(_:)` (line 341-348):
   - Add `self.cancelAutoArmTimer()` at start

4. Update `trustedDeviceAway(_:)` (line 351-354):
   - Check settings and call `startAutoArmTimer()`

5. Update `disarm()` (line 163-178):
   - Add `cancelAutoArmTimer()` to cleanup

### Phase 3: Settings UI (15 min)

**File:** `Views/SettingsView.swift`

After line 159 (Detection Distance picker), add:
- Toggle for `autoArmOnDeviceLeave`
- Conditional Picker for `autoArmGracePeriod`

## Testing Checklist

- [ ] Toggle off by default
- [ ] Grace period picker only visible when toggle on
- [ ] Timer cancelled if device returns within grace period
- [ ] Auto-arm triggers after grace period expires
- [ ] Screen locks if `autoLockOnArm` enabled
- [ ] No action if already armed
- [ ] Timer cancelled on manual disarm

## Edge Cases

1. **Device briefly loses signal** - Grace period handles this (debounce)
2. **User manually arms before timer** - Timer cancelled in arm check
3. **App quit while timer pending** - Timer invalidated on process end, no issue
4. **Bluetooth off** - No trustedDeviceAway callback, no trigger
