# MacGuard System Architecture

**Version:** 1.3.4 (Build 2)
**Last Updated:** 2025-12-19

## Overview

MacGuard is a menu bar application built with SwiftUI that monitors for unauthorized laptop access and triggers an alarm when threats are detected. The architecture follows a state machine pattern with clear separation between monitoring, state management, UI, and authentication layers.

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                          Menu Bar UI                            │
│                    (MenuBarView, SwiftUI)                       │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                    AlarmStateManager                            │
│                   (Core State Machine)                          │
│  States: idle → armed → triggered → alarming                   │
└─┬───────────┬───────────┬───────────┬───────────┬──────────────┘
  │           │           │           │           │
  ▼           ▼           ▼           ▼           ▼
┌────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌──────────────┐
│ Input  │ │ Sleep   │ │ Power   │ │Bluetooth│ │Auth          │
│Monitor │ │Monitor  │ │Monitor  │ │Proximity│ │Manager       │
└────────┘ └─────────┘ └─────────┘ └─────────┘ └──────────────┘
    │           │           │           │           │
    ▼           ▼           ▼           ▼           ▼
┌────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌──────────────┐
│CGEvent │ │ IOKit   │ │ IOKit   │ │CoreBT   │ │LocalAuth     │
│  Tap   │ │ (lid)   │ │ (power) │ │ (RSSI)  │ │+ Keychain    │
└────────┘ └─────────┘ └─────────┘ └─────────┘ └──────────────┘
```

## State Machine

### State Diagram

```
┌─────────┐
│  IDLE   │ ◄─────────────────────────────────┐
│         │                                    │
└────┬────┘                                    │
     │                                         │
     │ arm()                                   │
     ▼                                         │
┌─────────┐                                    │
│  ARMED  │                                    │
│         │ ◄──────────┐                       │
└────┬────┘            │                       │
     │                 │                       │
     │ input detected  │ authenticate()        │
     │ lid closed      │ during countdown      │
     │ power disconnect│                       │
     │                 │                       │
     ▼                 │                       │
┌─────────┐            │                       │
│TRIGGERED│────────────┘                       │
│ (3 sec) │                                    │
└────┬────┘                                    │
     │                                         │
     │ countdown expires                       │
     ▼                                         │
┌─────────┐                                    │
│ALARMING │                                    │
│         │────────────────────────────────────┘
└─────────┘  authenticate() → disarm()
```

### State Descriptions

| State | Description | Monitoring Active | Audio Playing | User Actions |
|-------|-------------|------------------|---------------|--------------|
| **idle** | Disarmed, not monitoring | No | No | Arm alarm, configure settings |
| **armed** | Monitoring for threats | Yes (input, sleep, power, Bluetooth) | No | Disarm, trigger on event |
| **triggered** | 3-second countdown | Yes | No | Authenticate to cancel, wait for alarm |
| **alarming** | Loud alarm playing | Yes | Yes (max volume) | Authenticate to disarm |

### State Transitions

| From | To | Trigger | Action |
|------|----|---------|---------|
| idle | armed | User clicks "Arm MacGuard" | Start monitors, optionally lock screen |
| armed | idle | User clicks "Disarm" or Bluetooth proximity | Stop monitors, restore sleep settings |
| armed | triggered | Input/sleep/power event detected | Start 3-second countdown timer |
| triggered | armed | User authenticates during countdown | Cancel countdown, resume armed state |
| triggered | alarming | Countdown timer expires | Play alarm at max volume |
| alarming | idle | User authenticates | Stop alarm, disarm, restore sleep settings |

## Component Architecture

### 1. State Management Layer

#### AlarmStateManager (357 LOC)
**Responsibilities:**
- Central state machine orchestration
- Coordinate all monitors (input, sleep, power, Bluetooth)
- Manage countdown timers
- Trigger audio playback
- Handle authentication callbacks
- Control screen lock

**Key Properties:**
```swift
@Published var currentState: AlarmState = .idle
@Published var countdownSeconds: Int = 3
private var inputMonitor: InputMonitor?
private var sleepMonitor: SleepMonitor?
private var powerMonitor: PowerMonitor?
private var proximityManager: BluetoothProximityManager?
```

**Key Methods:**
```swift
func arm()                           // Transition to armed state
func disarm()                        // Transition to idle state
func triggerAlarm()                  // Transition to triggered state
func handleAuthentication(success:)  // Handle auth callbacks
```

**Design Pattern:** Singleton with Combine @Published properties

### 2. Monitoring Layer

#### InputMonitor (144 LOC)
**Responsibilities:**
- Global keyboard, mouse, trackpad event monitoring
- CGEventTap for low-level event capture
- Filter events from MacGuard itself

**Key Technologies:**
- CoreGraphics (CGEventTap)
- Accessibility permission required

**Event Flow:**
```
User Input → CGEventTap → InputMonitor → Delegate → AlarmStateManager → triggered
```

#### SleepMonitor (248 LOC)
**Responsibilities:**
- Lid open/close detection via IOKit
- Sleep prevention when "lid close alarm" enabled
- Execute `pmset disablesleep` (requires admin)
- Restore sleep state on disarm

**Key Technologies:**
- IOKit framework
- IOPMAssertionCreateWithName for sleep prevention
- Process execution for pmset commands

**Event Flow:**
```
Lid Close → IOKit Callback → SleepMonitor → Delegate → AlarmStateManager → triggered
```

#### PowerMonitor (106 LOC)
**Responsibilities:**
- AC power source monitoring
- Detect power cable connect/disconnect events
- Filter battery percentage changes

**Key Technologies:**
- IOKit framework
- IOPSNotificationCreateRunLoopSource for power notifications

**Event Flow:**
```
Power Disconnect → IOKit Callback → PowerMonitor → Delegate → AlarmStateManager → triggered
```

#### BluetoothProximityManager (250 LOC)
**Responsibilities:**
- Scan for trusted Bluetooth device
- Monitor RSSI signal strength
- Auto-disarm when device is nearby (RSSI > -60 dB)
- Device selection and pairing

**Key Technologies:**
- CoreBluetooth framework
- CBCentralManager for scanning
- RSSI-based proximity detection

**Proximity Logic:**
```swift
// RSSI threshold: -60 dB (~5-10 meter range)
var isInProximity: Bool {
    return rssi > -60
}
```

**Auto-Disarm Flow:**
```
Bluetooth Scan → RSSI > -60 → ProximityManager → Delegate → AlarmStateManager → disarm()
```

### 3. Authentication Layer

#### AuthManager (145 LOC)
**Responsibilities:**
- Touch ID authentication via LocalAuthentication
- PIN fallback (4-8 digits)
- Secure PIN storage in Keychain
- PIN setup and validation

**Key Technologies:**
- LocalAuthentication framework
- Security framework (Keychain)

**Authentication Flow:**
```
User Action → Touch ID Prompt → Success/Failure → PIN Fallback (if needed) → AuthManager → AlarmStateManager
```

**Keychain Storage:**
```swift
// Keychain key: "com.MacGuard.PIN"
let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrAccount as String: "com.MacGuard.PIN",
    kSecValueData as String: pinData
]
```

### 4. Audio Layer

#### AlarmAudioManager (173 LOC)
**Responsibilities:**
- Play alarm sound at maximum volume
- Support system sounds and custom audio files
- Volume override (ignore user settings)
- Preview mode for testing sounds

**Key Technologies:**
- AVFoundation (AVAudioPlayer)
- CoreAudio (volume control)

**Audio Playback Flow:**
```
AlarmStateManager.alarming → AlarmAudioManager.play() → Set volume to max → AVAudioPlayer
```

**Bundled Sounds:**
- `dont-touch-my-mac.mp3` (default)
- `alarm.aiff` (alternative)
- 14 system sounds (Basso, Blow, Bottle, etc.)

### 5. Update Layer

#### UpdateManager (40 LOC)
**Responsibilities:**
- Initialize Sparkle auto-update framework
- Provide "Check for Updates" menu item
- Daily update checks (86400 seconds)

**Key Technologies:**
- Sparkle 2.x framework
- SPUStandardUpdaterController

**Update Flow:**
```
Daily Timer → Sparkle Check → appcast.xml → Download DMG → Install → Relaunch
```

**Known Issue:**
- Potential memory leak (reported in plans/reports)

### 6. UI Layer

#### MenuBarView (256 LOC)
**Responsibilities:**
- Menu bar dropdown interface
- Arm/Disarm button
- Quick status display
- Settings and quit buttons

**UI Framework:** SwiftUI (MenuBarExtra)

**State Binding:**
```swift
@ObservedObject var stateManager = AlarmStateManager.shared
```

#### SettingsView (575 LOC)
**Responsibilities:**
- Comprehensive settings window with 6 sections:
  1. **Permissions:** Accessibility, Bluetooth status + grant buttons
  2. **Device:** Trusted device scanner
  3. **Security:** PIN setup, Touch ID toggle
  4. **Behavior:** Auto-lock, lid close alarm, launch at login
  5. **Sound:** Alarm sound picker, volume slider, preview
  6. **About:** Version info, GitHub link, update checker

**UI Framework:** SwiftUI

**State Binding:**
```swift
@ObservedObject var settings = AppSettings.shared
```

#### CountdownOverlayView (326 LOC)
**Responsibilities:**
- Fullscreen countdown/alarm overlay
- 3-second countdown timer display
- Touch ID authentication button
- PIN entry fallback
- Block all user input

**UI Framework:** SwiftUI

**Overlay Management:**
```swift
CountdownWindowController.shared.show()  // Fullscreen window
CountdownWindowController.shared.hide()  // Dismiss
```

#### CountdownWindowController (86 LOC)
**Responsibilities:**
- Create fullscreen NSWindow for overlay
- Set window level (above all other windows)
- Manage window visibility and lifecycle

**Design Pattern:** Singleton

**Window Configuration:**
```swift
window.level = .floating  // Above all other windows
window.styleMask = [.borderless, .fullSizeContentView]
window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
```

#### DeviceScannerView (352 LOC)
**Responsibilities:**
- Bluetooth device scanner for trusted device pairing
- List only paired devices (no strangers)
- Show RSSI signal strength
- Device selection and removal

**UI Framework:** SwiftUI

#### PINEntryView (140 LOC)
**Responsibilities:**
- PIN setup and entry interface
- 4-8 digit PIN input
- Secure text field (masked input)
- Setup vs. verification modes

**UI Framework:** SwiftUI

#### SettingsWindowController (76 LOC)
**Responsibilities:**
- Create NSWindow for settings
- Manage window visibility and focus
- Single window instance

**Design Pattern:** Singleton

### 7. Model Layer

#### AlarmState (35 LOC)
**Type:** Enum
```swift
enum AlarmState {
    case idle       // Disarmed, not monitoring
    case armed      // Monitoring input, sleep, power
    case triggered  // 3-second countdown active
    case alarming   // Loud alarm playing
}
```

#### AppSettings (177 LOC)
**Type:** ObservableObject class
**Storage:** UserDefaults

**Properties:**
```swift
@AppStorage("selectedSound") var selectedSound: String = "dont-touch-my-mac.mp3"
@AppStorage("alarmVolume") var alarmVolume: Double = 1.0
@AppStorage("autoLockEnabled") var autoLockEnabled: Bool = true
@AppStorage("lidCloseAlarmEnabled") var lidCloseAlarmEnabled: Bool = false
@AppStorage("trustedDeviceUUID") var trustedDeviceUUID: String?
@AppStorage("launchAtLogin") var launchAtLogin: Bool = false
```

#### TrustedDevice (39 LOC)
**Type:** Struct

**Properties:**
```swift
var uuid: UUID              // Bluetooth UUID
var name: String            // Device name
var rssi: Double            // Signal strength
var isInProximity: Bool {   // Computed property
    return rssi > -60
}
```

### 8. Utility Layer

#### ResourceBundle (~30 LOC)
**Responsibilities:**
- Locate Resources directory in both development and production builds
- Resolve bundled audio files and icons
- SPM-compatible bundle resolution

**Bundle Resolution:**
```swift
static let bundle: Bundle = {
    #if SWIFT_PACKAGE
        return Bundle.module
    #else
        return Bundle.main
    #endif
}()
```

## Data Flow

### Arming Alarm
```
User clicks "Arm" → MenuBarView → AlarmStateManager.arm()
    ↓
AlarmStateManager transitions: idle → armed
    ↓
Start monitors:
    - InputMonitor.start()
    - SleepMonitor.start()
    - PowerMonitor.start()
    - BluetoothProximityManager.start()
    ↓
Optional: Lock screen (if autoLockEnabled)
    ↓
UI updates: Menu bar icon changes, button label → "Disarm"
```

### Triggering Alarm
```
Event detected (input/sleep/power)
    ↓
Monitor delegate calls AlarmStateManager
    ↓
AlarmStateManager transitions: armed → triggered
    ↓
Start 3-second countdown timer
    ↓
Show fullscreen overlay (CountdownOverlayView)
    ↓
Countdown expires (if no auth)
    ↓
AlarmStateManager transitions: triggered → alarming
    ↓
AlarmAudioManager.play() at max volume
    ↓
Await authentication to disarm
```

### Disarming Alarm
```
User authenticates (Touch ID or PIN)
    ↓
AuthManager validates credentials
    ↓
AuthManager callback → AlarmStateManager.handleAuthentication(success: true)
    ↓
AlarmStateManager transitions: alarming/triggered/armed → idle
    ↓
Stop all monitors
    ↓
Stop audio playback
    ↓
Restore sleep settings (if lid close alarm was enabled)
    ↓
Hide countdown overlay
    ↓
UI updates: Menu bar icon changes, button label → "Arm MacGuard"
```

### Bluetooth Auto-Disarm
```
BluetoothProximityManager scans (when armed)
    ↓
Detect trusted device with RSSI > -60 dB
    ↓
Delegate calls AlarmStateManager.handleProximityChange(inProximity: true)
    ↓
AlarmStateManager transitions: armed → idle
    ↓
Stop all monitors
    ↓
UI updates: Status → "Auto-disarmed (Bluetooth proximity)"
```

## Security Architecture

### Permission Model

| Permission | Required | Fallback Behavior |
|------------|----------|-------------------|
| **Accessibility** | Yes | App unusable (input monitoring disabled) |
| **Bluetooth** | No | Proximity auto-disarm disabled |
| **Administrator** | No | Lid close alarm disabled |

### Permission Granting Flow
```
SettingsView → Check permission status → Display status + "Grant" button
    ↓
User clicks "Grant"
    ↓
Open System Preferences → Privacy & Security → [Permission Type]
    ↓
User enables permission
    ↓
App detects permission grant (polling or relaunch)
    ↓
UI updates: Status → "Granted" (green checkmark)
```

### Authentication Hierarchy
1. **Bluetooth Proximity** (auto-disarm, no user interaction)
2. **Touch ID** (primary, requires user interaction)
3. **PIN** (fallback, requires user interaction)

### Data Storage Security

| Data | Storage | Encryption | Justification |
|------|---------|------------|---------------|
| **PIN** | Keychain | Yes (Keychain default) | Sensitive authentication credential |
| **Trusted Device UUID** | UserDefaults | No | Non-sensitive identifier |
| **App Settings** | UserDefaults | No | Non-sensitive preferences |
| **Alarm State** | In-Memory | N/A | Transient state |

## Performance Characteristics

### Resource Usage (Estimated)

| State | Memory (MB) | CPU (%) | Battery Impact |
|-------|------------|---------|----------------|
| idle | ~50 | <1% | Minimal |
| armed | ~80 | <2% | Low (monitoring overhead) |
| triggered | ~85 | ~3% | Low (countdown timer) |
| alarming | ~90 | ~5% | Moderate (audio playback) |

### Latency Metrics

| Event | Target Latency | Actual Latency |
|-------|---------------|----------------|
| Input detection | <100ms | ~50ms (CGEventTap) |
| Lid close detection | <500ms | ~200ms (IOKit callback) |
| Power disconnect detection | <1s | ~500ms (IOKit callback) |
| Bluetooth proximity detection | <3s | ~2s (scan interval) |
| Alarm trigger | <1s | ~500ms (state transition + audio load) |
| Touch ID authentication | <2s | ~1s (LocalAuthentication) |

### Scalability Constraints
- **Single instance:** One alarm state per app instance
- **Single device:** One trusted Bluetooth device (future: multiple devices)
- **Single window:** One countdown overlay (fullscreen, blocks all input)

## Error Handling

### Permission Errors
```swift
// Accessibility permission denied
if !hasAccessibilityPermission {
    print("Accessibility permission required for input monitoring")
    // Show alert in UI, disable arming
}
```

### Monitor Errors
```swift
// CGEventTap failure
guard let eventTap = CGEvent.tapCreate(...) else {
    print("Failed to create CGEventTap (Accessibility permission may be revoked)")
    return
}
```

### Authentication Errors
```swift
// Touch ID failure → fallback to PIN
context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, ...) { success, error in
    if success {
        completion(.success(()))
    } else {
        // Show PIN entry view
    }
}
```

### Audio Errors
```swift
// Audio file not found
guard let url = bundle.url(forResource: soundName, withExtension: "mp3") else {
    print("Sound file not found: \(soundName)")
    // Fallback to system sound
    return
}
```

## Deployment Architecture

### Build Artifacts
```
MacGuard.app/
├── Contents/
│   ├── MacOS/
│   │   └── MacGuard              # Executable binary
│   ├── Frameworks/
│   │   └── Sparkle.framework     # Auto-update framework
│   ├── Resources/
│   │   ├── AppIcon.icns
│   │   ├── MenuBarIcon.png
│   │   ├── dont-touch-my-mac.mp3
│   │   └── alarm.aiff
│   ├── Info.plist                # Bundle configuration
│   └── MacGuard.entitlements     # Permissions
```

### Distribution Flow
```
Source Code → swift build -c release → create-dmg.sh
    ↓
MacGuard.app bundle
    ↓
DMG creation (hdiutil)
    ↓
EdDSA signing (appcast.xml)
    ↓
GitHub Release
    ↓
User Download → Install → Sparkle auto-update
```

### CI/CD Pipeline
```
PR Merge to main → GitHub Actions trigger
    ↓
1. Setup certificate (optional, from secrets)
2. swift build -c release
3. scripts/create-dmg.sh
4. Sign appcast.xml (EdDSA)
5. Create GitHub Release
6. Upload DMG as release asset
7. Update appcast.xml in repo
    ↓
Sparkle detects update → User notified → Auto-download and install
```

## Dependency Graph

```
MacGuardApp
    ├── AlarmStateManager
    │   ├── InputMonitor (CGEventTap)
    │   ├── SleepMonitor (IOKit)
    │   ├── PowerMonitor (IOKit)
    │   ├── BluetoothProximityManager (CoreBluetooth)
    │   ├── AuthManager (LocalAuthentication, Keychain)
    │   └── AlarmAudioManager (AVFoundation)
    ├── MenuBarView (SwiftUI)
    ├── SettingsView (SwiftUI)
    │   ├── AppSettings (UserDefaults)
    │   └── DeviceScannerView (SwiftUI)
    ├── CountdownOverlayView (SwiftUI)
    │   └── CountdownWindowController (NSWindow)
    ├── UpdateManager (Sparkle)
    └── ResourceBundle (Bundle resolution)
```

## External Dependencies

| Dependency | Version | Purpose | License |
|------------|---------|---------|---------|
| Sparkle | 2.x | Auto-update framework | MIT |

## System Frameworks

| Framework | Purpose | Permission Required |
|-----------|---------|-------------------|
| SwiftUI | UI framework | No |
| Combine | Reactive programming | No |
| CoreGraphics | CGEventTap (input monitoring) | Accessibility |
| IOKit | Lid/power detection | Administrator (for pmset) |
| CoreBluetooth | Bluetooth proximity | Bluetooth |
| LocalAuthentication | Touch ID | No |
| Security | Keychain (PIN storage) | No |
| AVFoundation | Audio playback | No |
| CoreAudio | Volume control | No |
| ServiceManagement | Launch at login | No |

## Future Architecture Improvements

### Testability
- Dependency injection for managers (instead of singletons)
- Protocol-based monitor interfaces (mock implementations for tests)
- Separate business logic from UI (MVVM pattern)

### Modularity
- Extract monitors into separate Swift Package
- Extract UI components into reusable library
- Separate Settings into dedicated module

### Performance
- Optimize Bluetooth scanning (reduce power consumption)
- Lazy initialization for heavy resources
- Reduce memory footprint in armed state

### Reliability
- Fix UpdateManager memory leak
- Add error recovery for monitor failures
- Implement health checks for monitors

### Scalability
- Support multiple trusted devices
- Support custom countdown durations
- Support multiple alarm sounds (playlist)
