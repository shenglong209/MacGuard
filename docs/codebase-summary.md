# MacGuard Codebase Summary

**Version:** 1.3.4 (Build 2)
**Language:** Swift 5.9+
**Platform:** macOS 13.0 Ventura or later
**Total LOC:** ~4,350 lines (Swift source files only)

## Directory Structure

```
MacGuard/
├── Managers/          # 8 manager classes (business logic)
├── Models/            # 3 data models
├── Views/             # 7 SwiftUI views + window controllers
├── Utilities/         # 1 utility class (ResourceBundle)
├── Resources/         # Icons, audio files, assets
├── scripts/           # Build/release automation
├── .github/workflows/ # CI/CD automation
└── MacGuardApp.swift  # App entry point
```

## Source Files by Size

| File | LOC | Purpose |
|------|----:|---------|
| SettingsView.swift | 575 | Comprehensive settings UI (permissions, device, security, behavior) |
| AlarmStateManager.swift | 357 | Core state machine orchestrating all alarm logic |
| DeviceScannerView.swift | 352 | Bluetooth device scanner for trusted device pairing |
| CountdownOverlayView.swift | 326 | Fullscreen countdown/alarm overlay with authentication |
| MenuBarView.swift | 256 | Menu bar dropdown interface |
| BluetoothProximityManager.swift | 250 | RSSI-based proximity detection and auto-disarm |
| SleepMonitor.swift | 248 | Lid close detection + sleep prevention (IOKit) |
| AppSettings.swift | 177 | User preferences model with UserDefaults persistence |
| AlarmAudioManager.swift | 173 | Audio playback at max volume |
| AuthManager.swift | 145 | Touch ID + PIN authentication (Keychain-backed) |
| InputMonitor.swift | 144 | CGEventTap for global keyboard/mouse/trackpad monitoring |
| PINEntryView.swift | 140 | PIN setup and entry interface |
| PowerMonitor.swift | 106 | Power cable connect/disconnect detection |
| CountdownWindowController.swift | 86 | Overlay window lifecycle management |
| SettingsWindowController.swift | 76 | Settings window lifecycle management |
| MacGuardApp.swift | 71 | SwiftUI App entry point (MenuBarExtra) |
| UpdateManager.swift | 40 | Sparkle auto-update integration |
| TrustedDevice.swift | 39 | Bluetooth device model (UUID, name, RSSI, proximity) |
| AlarmState.swift | 35 | Enum: idle, armed, triggered, alarming |
| ResourceBundle.swift | ~30 | SPM/app bundle resource resolution |

**Total:** 18 Swift files, ~4,350 LOC

## Managers (8 files)

### AlarmStateManager.swift (357 LOC)
- **Purpose:** Core state machine orchestrating all alarm behavior
- **Responsibilities:**
  - State transitions (idle → armed → triggered → alarming)
  - Coordinates all monitors (Input, Sleep, Power, Bluetooth)
  - Manages countdown timers
  - Handles authentication callbacks
  - Controls screen lock and audio playback
- **Design Pattern:** State Machine + Delegate Pattern
- **Key Methods:** `arm()`, `disarm()`, `triggerAlarm()`, `handleAuthentication()`

### InputMonitor.swift (144 LOC)
- **Purpose:** Global input monitoring via CGEventTap
- **Responsibilities:**
  - Detects keyboard, mouse, and trackpad events
  - Requires Accessibility permission
  - Delegates input events to AlarmStateManager
- **Frameworks:** CoreGraphics (CGEventTap)

### SleepMonitor.swift (248 LOC)
- **Purpose:** Lid close detection and sleep prevention
- **Responsibilities:**
  - Monitors lid open/close events via IOKit
  - Prevents sleep when "lid close alarm" is enabled
  - Executes `pmset disablesleep` (requires admin permission)
  - Restores sleep state on disarm
- **Frameworks:** IOKit
- **Permissions:** Administrator (for pmset)

### PowerMonitor.swift (106 LOC)
- **Purpose:** Power cable connect/disconnect detection
- **Responsibilities:**
  - Monitors AC power source changes
  - Triggers alarm on power disconnect when armed
- **Frameworks:** IOKit

### BluetoothProximityManager.swift (250 LOC)
- **Purpose:** RSSI-based proximity detection for auto-disarm
- **Responsibilities:**
  - Scans for paired Bluetooth devices
  - Monitors RSSI signal strength
  - Auto-disarms when trusted device is nearby (RSSI > -60 dB)
  - Stores trusted device UUID in UserDefaults
- **Frameworks:** CoreBluetooth
- **Permissions:** Bluetooth

### AuthManager.swift (145 LOC)
- **Purpose:** Secure authentication for disarming alarm
- **Responsibilities:**
  - Touch ID authentication via LocalAuthentication
  - PIN fallback (4-8 digits stored in Keychain)
  - PIN setup and validation
- **Frameworks:** LocalAuthentication, Security (Keychain)
- **Keychain Key:** `com.MacGuard.PIN`

### AlarmAudioManager.swift (173 LOC)
- **Purpose:** Audio playback at maximum volume
- **Responsibilities:**
  - Plays system sounds or custom audio files
  - Forces volume to max when alarming
  - Supports 14 system sounds + custom files
  - Bundled sound: "Don't Touch My Mac" (dont-touch-my-mac.mp3)
- **Frameworks:** AVFoundation, CoreAudio

### UpdateManager.swift (40 LOC)
- **Purpose:** Sparkle auto-update integration
- **Responsibilities:**
  - Initializes SPUStandardUpdaterController
  - Provides "Check for Updates" menu item
  - Configured for daily update checks (86400 seconds)
- **Framework:** Sparkle 2.x
- **Known Issue:** Potential memory leak (reported in plans/reports)

## Models (3 files)

### AlarmState.swift (35 LOC)
- **Type:** Enum
- **States:**
  - `idle` - Disarmed, not monitoring
  - `armed` - Monitoring input, sleep, power
  - `triggered` - 3-second countdown active
  - `alarming` - Loud alarm playing

### AppSettings.swift (177 LOC)
- **Type:** ObservableObject class
- **Purpose:** User preferences with UserDefaults persistence
- **Properties:**
  - `selectedSound` - Alarm sound (system or custom)
  - `alarmVolume` - Volume level (0.0-1.0)
  - `autoLockEnabled` - Lock screen when armed
  - `lidCloseAlarmEnabled` - Instant alarm on lid close
  - `trustedDeviceUUID` - Paired Bluetooth device UUID
  - `launchAtLogin` - Launch app on system startup

### TrustedDevice.swift (39 LOC)
- **Type:** Struct
- **Purpose:** Bluetooth device model
- **Properties:**
  - `uuid` - Bluetooth UUID
  - `name` - Device name
  - `rssi` - Signal strength
  - `isInProximity` - Computed property (RSSI > -60 dB)

## Views (7 files)

### MenuBarView.swift (256 LOC)
- **Purpose:** Menu bar dropdown interface
- **Features:**
  - Arm/Disarm button
  - Quick status display
  - Settings button
  - Quit option
- **UI Framework:** SwiftUI

### SettingsView.swift (575 LOC)
- **Purpose:** Comprehensive settings window
- **Sections:**
  - **Permissions:** Accessibility, Bluetooth status and grant buttons
  - **Device:** Trusted device scanner
  - **Security:** PIN setup, Touch ID toggle
  - **Behavior:** Auto-lock, lid close alarm, launch at login
  - **Sound:** Alarm sound picker, volume slider with preview
  - **About:** Version info, GitHub link, update checker
- **UI Framework:** SwiftUI

### CountdownOverlayView.swift (326 LOC)
- **Purpose:** Fullscreen countdown/alarm overlay
- **Features:**
  - 3-second countdown timer
  - Touch ID authentication button
  - PIN entry fallback
  - Alarm state display
  - Blocks all user input
- **UI Framework:** SwiftUI

### CountdownWindowController.swift (86 LOC)
- **Purpose:** Overlay window lifecycle manager
- **Responsibilities:**
  - Creates fullscreen window
  - Sets window level (above all other windows)
  - Manages window visibility
- **Design Pattern:** Singleton

### DeviceScannerView.swift (352 LOC)
- **Purpose:** Bluetooth device scanner for trusted device pairing
- **Features:**
  - Lists only paired devices
  - Shows RSSI signal strength
  - Device selection and removal
  - Scanning indicator
- **UI Framework:** SwiftUI

### PINEntryView.swift (140 LOC)
- **Purpose:** PIN setup and entry interface
- **Features:**
  - 4-8 digit PIN input
  - Secure text field
  - Setup vs. verification modes
- **UI Framework:** SwiftUI

### SettingsWindowController.swift (76 LOC)
- **Purpose:** Settings window lifecycle manager
- **Responsibilities:**
  - Creates NSWindow for settings
  - Manages window visibility and focus
- **Design Pattern:** Singleton

## Utilities (1 file)

### ResourceBundle.swift (~30 LOC)
- **Purpose:** SPM/app bundle resource resolution
- **Responsibilities:**
  - Locates Resources directory in both development and production builds
  - Resolves bundled audio files and icons

## Configuration Files

### Info.plist
- **Bundle ID:** com.shenglong.macguard
- **Version:** 1.3.4 (CFBundleShortVersionString)
- **Build:** 2 (CFBundleVersion)
- **Min macOS:** 13.0 Ventura
- **Sparkle Config:**
  - Feed URL: `https://raw.githubusercontent.com/shenglong209/MacGuard/main/appcast.xml`
  - Update check interval: 86400 seconds (daily)
  - EdDSA public key: `hOFyiKPFGLs9oXEU5vb9r8jA+LfbgOMRMqgxJm37tnY=`

### MacGuard.entitlements
- **App Sandbox:** Disabled (required for Accessibility API)
- **Bluetooth:** Enabled
- **Apple Events:** Enabled (for volume control)

### Package.swift
- **SPM Configuration:** Swift Package Manager manifest
- **Dependencies:**
  - Sparkle 2.x (`https://github.com/sparkle-project/Sparkle`)
- **Platforms:** macOS 13.0+
- **Products:** MacGuard executable

### appcast.xml
- **Purpose:** Sparkle update feed
- **Format:** RSS 2.0 with Sparkle extensions
- **Signing:** EdDSA signature per release
- **Hosted:** GitHub repository (raw.githubusercontent.com)

## Scripts (4 files)

### scripts/create-dmg.sh
- **Purpose:** DMG creation for distribution
- **Responsibilities:**
  - Builds release binary (`swift build -c release`)
  - Creates .app bundle structure
  - Copies Sparkle.framework
  - Bundles resources (icons, audio)
  - Generates DMG with hdiutil
- **Output:** `dist/MacGuard-{version}.dmg`

### scripts/release.sh
- **Purpose:** Manual release trigger
- **Responsibilities:**
  - Bumps version in Info.plist
  - Updates README.md version references
  - Commits and pushes to main
  - Creates git tag
- **Usage:** `./scripts/release.sh 1.2.3`

### scripts/setup-certificate.sh
- **Purpose:** CI certificate setup
- **Responsibilities:**
  - Decodes base64 P12 certificate from GitHub secrets
  - Imports certificate to macOS keychain
  - Sets keychain as default for codesign
- **CI Integration:** Used in `.github/workflows/release.yml`

### scripts/export-certificate.sh
- **Purpose:** Export dev certificate for CI
- **Responsibilities:**
  - Exports Apple Development certificate from Keychain
  - Encodes as base64 for GitHub secrets
  - Generates password-protected P12 file
- **Usage:** Run locally, then add to GitHub secrets

## CI/CD (1 file)

### .github/workflows/release.yml
- **Triggers:**
  - Push to `main` branch
  - Manual workflow_dispatch
- **Version Bumping:**
  - `release:major` label → major bump
  - `release:minor` label → minor bump
  - Default → patch bump
- **Steps:**
  1. Checkout repository
  2. Setup certificate (optional, from GitHub secrets)
  3. Build release (`swift build -c release`)
  4. Create DMG (`scripts/create-dmg.sh`)
  5. Sign appcast.xml (EdDSA)
  6. Create GitHub Release
  7. Upload DMG as release asset
  8. Update appcast.xml in repository
- **Secrets Required:**
  - `SIGNING_CERTIFICATE_P12_BASE64` (optional, preserves Accessibility permission)
  - `SIGNING_CERTIFICATE_PASSWORD` (optional)
  - `SPARKLE_PRIVATE_KEY` (required, for appcast signing)

## Dependencies

### External Frameworks

| Framework | Source | Version | Purpose |
|-----------|--------|---------|---------|
| Sparkle | SPM | 2.x | Auto-update mechanism |

### System Frameworks

| Framework | Purpose |
|-----------|---------|
| SwiftUI | UI framework |
| Combine | Reactive programming |
| CoreGraphics | CGEventTap for input monitoring |
| IOKit | Lid/power detection |
| CoreBluetooth | Bluetooth proximity detection |
| LocalAuthentication | Touch ID |
| Security | Keychain for PIN storage |
| AVFoundation | Audio playback |
| CoreAudio | Volume control |
| ServiceManagement | Launch at login |

## Permissions Required

| Permission | Purpose | Framework |
|------------|---------|-----------|
| Accessibility | Global input monitoring via CGEventTap | CoreGraphics |
| Bluetooth | Trusted device proximity detection | CoreBluetooth |
| Administrator | Lid close alarm (pmset disablesleep) | IOKit |

## Resources

### Icons
- `Resources/AppIcon.png` - Application icon (1024x1024)
- `Resources/MenuBarIcon.png` - Menu bar icon (template image)

### Audio
- `Resources/dont-touch-my-mac.mp3` - Bundled alarm sound (default)
- `Resources/alarm.aiff` - Alternative alarm sound

### Assets
- `featured-image.png` - Repository/marketing image

## Build Process

### Development Build
```bash
swift build
```

### Release Build
```bash
swift build -c release
./scripts/create-dmg.sh 1.3.4
```

### Output Locations
- Debug binary: `.build/debug/MacGuard`
- Release binary: `.build/release/MacGuard`
- DMG: `dist/MacGuard-{version}.dmg`

## Security Model

### Authentication Hierarchy
1. **Bluetooth Proximity** - Auto-disarm when trusted device is nearby (RSSI > -60 dB)
2. **Touch ID** - Primary authentication method
3. **PIN** - Fallback authentication (4-8 digits, Keychain-stored)

### Data Storage
- **UserDefaults:** App settings, trusted device UUID
- **Keychain:** PIN (key: `com.MacGuard.PIN`)
- **In-Memory:** Authentication state, alarm state

### Code Signing
- **Development:** Optional (app works without signing)
- **Production:** Recommended (preserves Accessibility permission across updates)
- **Certificate:** Apple Development or Apple Developer ID
- **Entitlements:** App Sandbox disabled, Bluetooth enabled, Apple Events enabled

## Known Issues

1. **UpdateManager Memory Leak** - Potential memory leak in Sparkle integration (reported in `plans/reports`)
2. **No Unit Tests** - Project lacks automated testing coverage
3. **Code Signing UX** - Unsigned apps require right-click → Open on first launch

## Future Considerations

See `docs/project-roadmap.md` for detailed roadmap and planned enhancements.
