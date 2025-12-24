# MacGuard - Product Development Requirements

**Version:** 2.0.1
**Last Updated:** 2025-12-24
**Status:** Production Release

## Vision & Goals

### Product Vision
MacGuard is an anti-theft alarm application for macOS that protects laptops in public places by triggering a loud alarm when unauthorized access is detected. The product provides peace of mind for users working in cafés, libraries, coworking spaces, and other public environments.

### Primary Goals
1. **Deterrence** - Prevent theft through visible alarm system and loud audio
2. **Detection** - Immediately detect unauthorized access attempts (input, lid close, power disconnect)
3. **Accessibility** - Simple, intuitive interface requiring minimal configuration
4. **Reliability** - Robust state management with no false positives/negatives
5. **Flexibility** - Configurable triggers, sounds, and authentication methods

### Success Criteria
- ✅ Zero false alarms when armed and undisturbed
- ✅ <1 second alarm trigger latency from input detection
- ✅ 100% alarm trigger rate for configured events
- ✅ <5 minutes setup time for new users
- ✅ Auto-disarm via Bluetooth proximity (>90% accuracy)

## Target Audience

### Primary Users
- **Digital Nomads** - Frequent travelers working from public spaces
- **Students** - Working in libraries, cafeterias, study rooms
- **Remote Workers** - Using cafés and coworking spaces
- **Conference Attendees** - Protecting laptops during networking events

### User Characteristics
- macOS users (13.0 Ventura or later)
- Concerned about laptop theft in public places
- Willing to grant Accessibility permission for security
- Own Bluetooth devices (iPhone, AirPods, Apple Watch) for auto-disarm
- Value simplicity over complex configuration

### Non-Goals
- Enterprise deployment (no MDM integration, no admin controls)
- Windows/Linux support
- Network-based tracking (no Find My Mac integration)
- Data encryption (focused on physical theft, not data security)

## Core Features

### 1. Alarm State Management
**Priority:** P0 (Critical)
**Status:** Complete

**Requirements:**
- Four-state system: idle, armed, triggered, alarming
- State transitions must be atomic and thread-safe
- Single source of truth for alarm state
- Observable state changes for UI updates

**Acceptance Criteria:**
- ✅ State transitions follow defined state machine
- ✅ No race conditions during concurrent monitor callbacks
- ✅ UI reflects state changes within 100ms
- ✅ State persists correctly across app lifecycle events

### 2. Input Monitoring
**Priority:** P0 (Critical)
**Status:** Complete

**Requirements:**
- Global keyboard, mouse, and trackpad event detection
- Requires Accessibility permission
- Event filtering (ignore events from MacGuard itself)
- Trigger alarm on any input when armed

**Acceptance Criteria:**
- ✅ Detects all keyboard input (except when disarming)
- ✅ Detects mouse movement and clicks
- ✅ Detects trackpad gestures
- ✅ No input monitoring when idle/disarmed
- ✅ Graceful handling of missing Accessibility permission

### 3. Lid Close Detection
**Priority:** P1 (High)
**Status:** Complete

**Requirements:**
- Instant alarm on lid close (no countdown)
- Prevent sleep when lid closes (optional, requires admin)
- Restore sleep behavior when disarmed
- User-configurable enable/disable toggle

**Acceptance Criteria:**
- ✅ Alarm triggers <500ms after lid close
- ✅ `pmset disablesleep` executed when enabled
- ✅ Sleep restored correctly after disarm
- ✅ Works with both clamshell and normal modes

**Technical Constraints:**
- Requires administrator permission for `pmset` command
- IOKit framework for lid detection

### 4. Power Disconnect Detection
**Priority:** P1 (High)
**Status:** Complete

**Requirements:**
- Alarm on AC power cable disconnect
- No alarm on battery percentage changes
- Trigger only when armed

**Acceptance Criteria:**
- ✅ Alarm triggers within 1 second of power disconnect
- ✅ No false triggers on power fluctuations
- ✅ Works with both MagSafe and USB-C power adapters

### 5. Bluetooth Proximity Auto-Disarm
**Priority:** P1 (High)
**Status:** Complete

**Requirements:**
- Scan for trusted Bluetooth devices (iPhone, AirPods, Apple Watch)
- Support up to 10 trusted devices
- Auto-disarm when ANY device is nearby (RSSI > threshold)
- Auto-arm when ALL devices leave proximity
- User selects trusted devices from paired devices only
- Proximity detection runs only when armed
- Legacy single-device data auto-migrates to new array format

**Acceptance Criteria:**
- RSSI threshold configurable (default -60 dB, ~5-10 meter range)
- Auto-disarm latency <3 seconds after any device enters proximity
- Auto-arm triggers when all trusted devices leave proximity
- No false disarms from non-trusted devices
- Graceful handling of Bluetooth permission denial
- Device list UI with add/remove functionality

**Technical Constraints:**
- CoreBluetooth requires Bluetooth permission
- RSSI values vary by device type and environment
- Scanning consumes battery power
- Max 10 devices (performance limit)

### 6. Touch ID + PIN Authentication
**Priority:** P0 (Critical)
**Status:** Complete

**Requirements:**
- Touch ID as primary authentication method
- PIN fallback (4-8 digits)
- Secure PIN storage in Keychain
- Authentication required to disarm triggered/alarming state

**Acceptance Criteria:**
- ✅ Touch ID prompt appears immediately on trigger
- ✅ PIN entry available if Touch ID fails
- ✅ PIN persists across app restarts
- ✅ No plaintext PIN storage

**Security Requirements:**
- PIN stored in Keychain with key: `com.MacGuard.PIN`
- LocalAuthentication framework for Touch ID
- No biometric data stored by app

### 7. Alarm Audio Playback
**Priority:** P0 (Critical)
**Status:** Complete

**Requirements:**
- Play alarm sound at maximum volume
- Support 14 system sounds + custom audio files
- Bundled default sound: "Don't Touch My Mac"
- Volume override (ignore user volume settings)
- Preview button for testing sounds

**Acceptance Criteria:**
- ✅ Alarm plays at max volume regardless of system volume
- ✅ Audio continues until authenticated disarm
- ✅ No audio glitches or delays
- ✅ Preview plays at configured volume (not max)

**Audio Specifications:**
- Supported formats: MP3, AIFF, WAV
- Bundled sound: dont-touch-my-mac.mp3
- System sounds: Basso, Blow, Bottle, Frog, Funk, Glass, Hero, Morse, Ping, Pop, Purr, Sosumi, Submarine, Tink

### 8. Menu Bar Interface
**Priority:** P0 (Critical)
**Status:** Complete

**Requirements:**
- Menu bar icon indicating armed/disarmed state
- Dropdown with Arm/Disarm button
- Quick access to Settings
- Quit option

**Acceptance Criteria:**
- ✅ Icon changes color/style based on state
- ✅ Arm/Disarm button reflects current state
- ✅ Menu bar remains accessible in all states
- ✅ No UI freezes or lag

### 9. Settings Window
**Priority:** P1 (High)
**Status:** Complete

**Requirements:**
- **Permissions Section:** Accessibility and Bluetooth status + grant buttons
- **Device Section:** Trusted device scanner and selection
- **Security Section:** PIN setup, Touch ID toggle
- **Behavior Section:** Auto-lock, lid close alarm, launch at login
- **Sound Section:** Alarm sound picker, volume slider, preview button
- **About Section:** Version info, GitHub link, update checker

**Acceptance Criteria:**
- ✅ All settings persist across app restarts
- ✅ Permission status updates in real-time
- ✅ Device scanner shows only paired devices
- ✅ Volume preview respects user volume settings
- ✅ Launch at login works via ServiceManagement

### 10. Auto-Update (Sparkle)
**Priority:** P1 (High)
**Status:** Complete

**Requirements:**
- Daily update checks (86400 seconds)
- EdDSA-signed appcast.xml for security
- Manual "Check for Updates" button in Settings
- DMG distribution via GitHub Releases
- Optional code signing to preserve Accessibility permission

**Acceptance Criteria:**
- ✅ Update checks occur daily in background
- ✅ User can manually trigger update check
- ✅ Appcast signature verified before download
- ✅ DMG downloads and installs correctly
- ✅ Accessibility permission preserved with code signing

**Technical Constraints:**
- Sparkle 2.x dependency via SPM
- EdDSA private key required for signing
- Appcast hosted on GitHub (raw.githubusercontent.com)

## Non-Functional Requirements

### Performance
- **Startup Time:** <2 seconds from launch to menu bar icon visible
- **Memory Usage:** <100 MB when armed
- **CPU Usage:** <2% when armed (idle monitoring)
- **Battery Impact:** <5% additional drain per hour when armed
- **Alarm Trigger Latency:** <1 second from event to audio playback

### Reliability
- **Uptime:** 99.9% (no crashes during normal operation)
- **State Consistency:** 100% (no undefined states)
- **False Positive Rate:** <0.1% (incorrect alarm triggers)
- **False Negative Rate:** 0% (missed alarm triggers)

### Security
- **PIN Storage:** Keychain-based, no plaintext
- **Bluetooth Security:** Trusted device UUID stored in UserDefaults (non-sensitive)
- **Code Signing:** Optional (recommended for preserving permissions)
- **Update Security:** EdDSA signature verification required

### Usability
- **Setup Time:** <5 minutes for new users
- **Permission Granting:** Guided prompts with "Grant" buttons
- **Error Messages:** Clear, actionable instructions
- **Accessibility:** VoiceOver compatible (SwiftUI default)

### Compatibility
- **macOS Version:** 13.0 Ventura or later
- **Architecture:** Universal binary (arm64 + x86_64)
- **Display:** Works on all screen sizes (adaptive layout)
- **Language:** English only (no localization)

### Maintainability
- **Code Standards:** Swift 5.9+, SwiftUI, Combine
- **Documentation:** Inline comments for complex logic
- **Versioning:** Semantic versioning (major.minor.patch)
- **CI/CD:** Automated releases via GitHub Actions

## Technical Requirements

### Architecture
- **Design Pattern:** State Machine (AlarmStateManager)
- **UI Framework:** SwiftUI
- **Reactive Programming:** Combine (@Published properties)
- **Dependency Injection:** Singleton managers with protocol-oriented design

### Dependencies
| Dependency | Version | Purpose |
|------------|---------|---------|
| Sparkle | 2.x | Auto-update mechanism |
| SwiftUI | Native | UI framework |
| Combine | Native | Reactive state management |
| CoreGraphics | Native | CGEventTap for input monitoring |
| IOKit | Native | Lid/power detection |
| CoreBluetooth | Native | Bluetooth proximity |
| LocalAuthentication | Native | Touch ID |
| Security | Native | Keychain for PIN |
| AVFoundation | Native | Audio playback |

### Permissions
| Permission | Required | Graceful Degradation |
|------------|----------|---------------------|
| Accessibility | Yes | App unusable without (input monitoring disabled) |
| Bluetooth | No | Proximity auto-disarm disabled |
| Administrator | No | Lid close alarm disabled |

### Data Storage
- **UserDefaults:** App settings, trusted devices array (JSON encoded)
- **Keychain:** PIN (key: `com.MacGuard.PIN`)
- **In-Memory:** Authentication state, alarm state, device proximity states

### Build & Distribution
- **Build Tool:** Swift Package Manager (SPM)
- **Distribution:** DMG via GitHub Releases
- **Update Mechanism:** Sparkle appcast.xml
- **Signing:** Optional code signing (preserves permissions)

## Success Metrics

### Adoption Metrics
- GitHub Stars: >100
- Releases Downloaded: >500
- Active Users: >200 (estimated from update checks)

### Quality Metrics
- Crash Rate: <0.1%
- False Alarm Rate: <0.1%
- Missed Alarm Rate: 0%
- Update Adoption: >80% within 7 days

### User Satisfaction
- GitHub Issues: <5 open bugs
- Feature Requests: Prioritized based on demand
- User Feedback: Positive tone in issues/discussions

## Roadmap Alignment

See `docs/project-roadmap.md` for detailed roadmap and planned enhancements.

### Completed Milestones
- Core alarm functionality (v1.0.0)
- Bluetooth proximity auto-disarm (v1.1.0)
- Sparkle auto-update integration (v1.2.0)
- CI/CD automation (v1.3.0)
- Multiple trusted devices support (v1.4.0)
- Major feature release: non-Apple BT, dynamic icon, Mac speaker (v2.0.0)

### Upcoming Milestones
- Unit test coverage (target: >80%)
- UpdateManager memory leak fix
- Custom countdown duration
- Notification on alarm trigger
- iCloud sync for settings

## Constraints & Limitations

### Technical Constraints
- **Accessibility Permission:** Required for core functionality (CGEventTap)
- **App Sandbox:** Disabled (incompatible with Accessibility API)
- **Administrator Permission:** Required for lid close alarm (pmset)
- **Bluetooth Range:** Limited to ~5-10 meters (RSSI threshold)

### Platform Constraints
- **macOS Only:** No Windows/Linux support
- **SwiftUI:** Requires macOS 13.0 Ventura or later
- **Sparkle:** Requires internet connection for update checks

### Business Constraints
- **Open Source:** MIT License (no commercial restrictions)
- **Solo Developer:** Limited bandwidth for feature development
- **No Monetization:** Free product (no revenue stream)

## Risk Assessment

### High-Risk Items
1. **Accessibility Permission Denial** - App unusable without it
   - **Mitigation:** Clear permission prompts, guided setup
2. **False Alarm Triggers** - User frustration and abandonment
   - **Mitigation:** Rigorous testing, state machine validation
3. **UpdateManager Memory Leak** - Crashes over time
   - **Mitigation:** Fix in next release, monitoring via logs

### Medium-Risk Items
1. **Bluetooth Proximity Accuracy** - RSSI variability
   - **Mitigation:** Configurable threshold, user testing
2. **Lid Close Detection** - IOKit framework complexity
   - **Mitigation:** Thorough testing on multiple MacBook models
3. **Code Signing UX** - Unsigned apps require right-click → Open
   - **Mitigation:** Documentation, optional code signing for CI

### Low-Risk Items
1. **Audio Playback Glitches** - Rare audio driver issues
   - **Mitigation:** Fallback to system sounds
2. **Sparkle Update Failures** - Network errors, signature mismatch
   - **Mitigation:** Retry logic, clear error messages

## Compliance & Legal

### Privacy
- No personal data collected or transmitted
- No analytics or telemetry
- No network requests (except Sparkle update checks)

### Open Source License
- MIT License (permissive, commercial use allowed)
- Copyright: Sheng Long (2024-2025)
- Repository: https://github.com/shenglong209/MacGuard

### Third-Party Licenses
- Sparkle: MIT License (compatible)
- No other third-party dependencies

## Appendix

### Glossary
- **RSSI:** Received Signal Strength Indicator (Bluetooth proximity metric)
- **CGEventTap:** macOS API for global event monitoring (requires Accessibility)
- **IOKit:** Low-level macOS framework for hardware interaction
- **Sparkle:** Open-source auto-update framework for macOS apps
- **EdDSA:** Edwards-curve Digital Signature Algorithm (appcast signing)

### References
- [GitHub Repository](https://github.com/shenglong209/MacGuard)
- [Sparkle Documentation](https://sparkle-project.org/documentation/)
- [Apple Developer Documentation](https://developer.apple.com/documentation/)
