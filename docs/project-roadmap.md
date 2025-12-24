# MacGuard Project Roadmap

**Version:** 1.4.0
**Last Updated:** 2025-12-24
**Status:** Production Release

## Completed Milestones

### v1.0.0 - Core Functionality (Initial Release)
**Status:** ✅ Complete

**Features Delivered:**
- ✅ State machine architecture (idle, armed, triggered, alarming)
- ✅ Input monitoring via CGEventTap (keyboard, mouse, trackpad)
- ✅ Sleep/lid close detection via IOKit
- ✅ Power disconnect detection
- ✅ Touch ID + PIN authentication
- ✅ Alarm audio playback at max volume
- ✅ Menu bar interface (SwiftUI)
- ✅ Settings window (permissions, sound, behavior)
- ✅ Fullscreen countdown overlay
- ✅ Keychain-based PIN storage

**Technical Achievements:**
- State machine with Combine @Published properties
- Delegate pattern for monitor coordination
- Singleton managers for global state
- SwiftUI-based UI with reactive updates

---

### v1.1.0 - Bluetooth Proximity Auto-Disarm
**Status:** ✅ Complete

**Features Delivered:**
- ✅ Bluetooth device scanning (paired devices only)
- ✅ RSSI-based proximity detection (threshold: -60 dB)
- ✅ Auto-disarm when trusted device is nearby
- ✅ Device scanner UI in Settings
- ✅ Trusted device UUID storage in UserDefaults

**Technical Achievements:**
- CoreBluetooth integration
- RSSI signal strength monitoring
- Proximity detection algorithm (~5-10 meter range)
- Real-time device list with signal strength indicators

---

### v1.2.0 - Sparkle Auto-Update Integration
**Status:** ✅ Complete

**Features Delivered:**
- ✅ Sparkle 2.x SPM integration
- ✅ Daily update checks (86400 seconds)
- ✅ EdDSA-signed appcast.xml
- ✅ Manual "Check for Updates" button in Settings
- ✅ DMG distribution via GitHub Releases

**Technical Achievements:**
- Swift Package Manager dependency management
- EdDSA key generation and signing workflow
- Appcast.xml hosting on GitHub (raw.githubusercontent.com)
- UpdateManager singleton for Sparkle lifecycle

**Known Issues Identified:**
- Potential memory leak in UpdateManager (reported in plans/reports)

---

### v1.3.0 - CI/CD Automation
**Status:** ✅ Complete

**Features Delivered:**
- ✅ GitHub Actions workflow for automated releases
- ✅ Version bumping via PR labels (major, minor, patch)
- ✅ Automated DMG creation
- ✅ EdDSA signing in CI
- ✅ GitHub Release creation with DMG upload
- ✅ Optional code signing to preserve Accessibility permission

**Technical Achievements:**
- `.github/workflows/release.yml` for automated builds
- `scripts/create-dmg.sh` for DMG packaging
- `scripts/setup-certificate.sh` for CI code signing
- `scripts/export-certificate.sh` for local certificate export
- PR label-based version bumping logic
- Sparkle framework bundling in DMG

**Releases Completed:**
- 11 DMG releases (v1.2.1 → v1.3.3)
- v1.3.4 (current)

---

### v1.3.4 - Documentation Release
**Status:** Complete (2025-12-19)

**Features Delivered:**
- Comprehensive documentation in `docs/` directory
- `docs/project-overview-pdr.md` - Product Development Requirements
- `docs/codebase-summary.md` - Technical summary
- `docs/code-standards.md` - Coding standards
- `docs/system-architecture.md` - Architecture details
- `docs/project-roadmap.md` - This document
- `docs/deployment-guide.md` - Build and release process

**Documentation Improvements:**
- Detailed architecture diagrams
- State machine documentation
- Data flow diagrams
- Security model documentation
- Performance metrics
- Build and deployment instructions

---

### v1.4.0 - Multiple Trusted Devices
**Status:** Complete (2025-12-24)

**Features Delivered:**
- Support for up to 10 trusted Bluetooth devices
- Auto-disarm when ANY trusted device enters proximity
- Auto-arm when ALL trusted devices leave proximity
- Device list UI with add/remove functionality
- Legacy single-device data auto-migration
- Updated delegate protocol with `allTrustedDevicesAway()`
- Per-device proximity state tracking

**Technical Achievements:**
- Array-based device storage (JSON encoded in UserDefaults)
- Hysteresis logic for RSSI thresholds (present vs away)
- Efficient multi-device scanning with connection management
- Backward-compatible API (`trustedDevice` property returns first device)

**Files Changed:**
- `BluetoothProximityManager.swift` - Array storage, multi-device tracking
- `AlarmStateManager.swift` - Updated delegate handling
- `SettingsView.swift` - Device list with add/remove UI
- `DeviceScannerView.swift` - Add mode instead of replace

---

## Known Issues

### High Priority (P0)

#### 1. UpdateManager Memory Leak
**Status:** 🔴 Open
**Priority:** P0 (Critical)
**Severity:** High

**Description:**
Potential memory leak in `UpdateManager.swift` (40 LOC) related to Sparkle framework integration.

**Impact:**
- Memory consumption increases over time
- Potential crash after extended uptime
- Affects long-running instances

**Root Cause:**
- Suspected strong reference cycle in Sparkle delegate callbacks
- Sparkle controller not properly cleaned up

**Mitigation:**
- Short-term: Recommend app restart every few days
- Long-term: Fix in next release

**Investigation Plan:**
1. Profile with Xcode Instruments (Leaks, Allocations)
2. Review Sparkle delegate implementation
3. Add weak references where needed
4. Test with extended uptime (7+ days)

**Target Fix Version:** v1.4.0

---

### Medium Priority (P1)

#### 2. No Unit Tests
**Status:** 🟡 Open
**Priority:** P1 (High)
**Severity:** Medium

**Description:**
Project lacks automated unit tests. Testing is currently manual and time-consuming.

**Impact:**
- Regression risk when making changes
- Slower development velocity
- Lower code quality confidence

**Target Coverage:** >80%

**Test Plan:**
1. **State Machine Tests** (AlarmStateManager)
   - Test all state transitions (idle → armed → triggered → alarming)
   - Test edge cases (multiple rapid transitions)
   - Test authentication callbacks

2. **Monitor Tests** (InputMonitor, SleepMonitor, PowerMonitor, BluetoothProximityManager)
   - Mock event detection
   - Test delegate callbacks
   - Test start/stop lifecycle

3. **Authentication Tests** (AuthManager)
   - Mock Touch ID success/failure
   - Test PIN validation logic
   - Test Keychain storage/retrieval

4. **Audio Tests** (AlarmAudioManager)
   - Test audio file loading
   - Test volume control
   - Test preview mode

**Target Implementation:** v1.4.0

---

#### 3. Bluetooth Proximity Accuracy
**Status:** 🟡 Open
**Priority:** P1 (High)
**Severity:** Low

**Description:**
RSSI-based proximity detection has variable accuracy depending on device type and environment.

**Impact:**
- False auto-disarms in noisy RF environments
- Delayed auto-disarm in metal-heavy environments
- Inconsistent user experience

**Current RSSI Threshold:** -60 dB (~5-10 meters)

**Proposed Improvements:**
1. **Configurable threshold** - Allow users to adjust sensitivity
2. **Hysteresis logic** - Require sustained proximity (5+ seconds)
3. **Multiple devices** - Use closest device among multiple trusted devices
4. **Filtering** - Average RSSI over multiple samples

**Target Implementation:** v1.5.0

---

### Low Priority (P2)

#### 4. Code Signing UX
**Status:** 🟢 Open
**Priority:** P2 (Low)
**Severity:** Low

**Description:**
Unsigned apps require right-click → Open on first launch due to macOS Gatekeeper.

**Impact:**
- Confusing first-launch experience
- Users may think app is malware
- Accessibility permission lost on update (if unsigned)

**Current Mitigation:**
- Documentation in README (right-click → Open)
- Alternative: `xattr -cr /Applications/MacGuard.app`
- Optional code signing in CI (preserves permissions)

**Proposed Solution:**
- Obtain Apple Developer ID certificate ($99/year)
- Notarize app with Apple (automated in CI)
- Code sign all releases

**Blocker:** Requires Apple Developer Program membership ($99/year)

**Target Implementation:** TBD (pending funding or sponsorship)

---

## Upcoming Milestones

### v1.5.0 - Quality & Reliability
**Status:** Planned
**Target:** Q1 2025

**Goals:**
- Fix UpdateManager memory leak
- Implement unit tests (>80% coverage)
- Add integration tests for state transitions
- Performance profiling and optimization

**Features:**
- UpdateManager memory leak fix (P0)
- Unit test suite (P1)
- CI test automation (run tests on PR)
- Memory profiling documentation
- Performance benchmarks

**Technical Debt:**
- Refactor SettingsView into smaller components (575 LOC → <300 LOC each)
- Extract constants into Constants.swift file
- Add SwiftLint configuration
- Improve error handling and logging

**Success Metrics:**
- Test coverage >80%
- Memory leak eliminated (confirmed via 7-day stress test)
- No performance regressions
- CI tests pass on all PRs

---

### v1.6.0 - Customization & Flexibility
**Status:** Planned
**Target:** Q2 2025

**Goals:**
- Custom countdown duration
- Notification on alarm trigger
- Alarm trigger history/logs
- iCloud sync for settings

**Features:**
- ✅ Configurable countdown (1-10 seconds)
- ✅ macOS notification on trigger (with sound)
- ✅ Alarm history log (last 100 events)
- ✅ iCloud sync for AppSettings
- ✅ Export settings to file (JSON)
- ✅ Import settings from file

**UI Changes:**
- Countdown duration slider in Settings
- Notification toggle in Settings
- History view in Settings (timestamp, trigger reason)
- iCloud sync toggle in Settings

**Technical Challenges:**
- CloudKit integration for iCloud sync
- Notification permissions (UserNotifications framework)
- Efficient history storage (CoreData or JSON file)

**Success Metrics:**
- iCloud sync works across multiple Macs
- Notification delivery <1 second after trigger
- History log accessible and searchable

---

### v2.0.0 - Major Redesign
**Status:** 💡 Idea
**Target:** Q4 2025

**Goals:**
- Redesigned UI (modern, minimal)
- Dark mode support
- Accessibility improvements (VoiceOver)
- Multiple alarm profiles (home, office, café)

**Features:**
- ✅ Complete UI redesign (Figma mockups)
- ✅ Native dark mode support
- ✅ VoiceOver full compatibility
- ✅ Alarm profiles (save/load configurations)
- ✅ Quick profile switching in menu bar
- ✅ Profile-specific sounds and volumes

**UI Changes:**
- New Settings window layout (tabbed interface)
- New menu bar dropdown (compact, modern)
- New countdown overlay (animations, transitions)
- Color scheme customization

**Technical Challenges:**
- SwiftUI dark mode support (AppStorage for theme)
- VoiceOver labels and hints for all UI elements
- Profile storage (CoreData or JSON)
- Migration from v1.x settings

**Success Metrics:**
- User satisfaction survey (>80% positive)
- Accessibility audit (100% VoiceOver compatible)
- Profile switching <1 second

---

## Future Considerations (No Timeline)

### Advanced Features
- **Network-based disarm** - Disarm via iMessage, Find My, or web portal
- **Geofencing** - Auto-arm when leaving trusted location (home)
- **Time-based arming** - Auto-arm at specific times (work hours)
- **Camera snapshot** - Capture photo of intruder via webcam
- **Remote alarm** - Trigger alarm remotely if laptop is stolen
- **Touch Bar support** - Quick arm/disarm for MacBook Pro

### Platform Expansion
- **iOS companion app** - Control MacGuard from iPhone
- **Apple Watch app** - Quick arm/disarm from wrist
- **iPadOS support** - Protect iPad with similar alarm
- **Cross-platform sync** - Shared settings across devices

### Integration
- **Find My integration** - Report location when alarm triggers
- **Shortcuts support** - Trigger automation with Shortcuts.app
- **Siri support** - Voice commands to arm/disarm
- **HomeKit integration** - Arm when leaving home scene

### Enterprise Features
- **MDM support** - Centralized configuration for organizations
- **Admin controls** - Disable user settings changes
- **Audit logs** - Track all alarm events for compliance
- **LDAP/AD integration** - Enterprise authentication

### Monetization (Optional)
- **Pro version** - Advanced features (profiles, iCloud sync, camera)
- **Sponsorships** - GitHub Sponsors for ongoing development
- **Donations** - One-time donations for feature requests

---

## Deprecation & Sunset

### Minimum macOS Version
- **Current:** macOS 13.0 Ventura
- **Future:** May increase to 14.0 Sonoma for new SwiftUI features
- **Timeline:** v2.0.0 (Q4 2025)

### Legacy Features
No legacy features planned for removal at this time.

---

## Community Feedback

### GitHub Issues
- **Open Bugs:** <5 (target)
- **Feature Requests:** Prioritized by community votes
- **Pull Requests:** Welcome (see CONTRIBUTING.md)

### User Surveys
- Planned for v1.5.0 (after Bluetooth improvements)
- Focus on usability and feature prioritization

---

## Release Cadence

### Current Cadence
- **Patch releases:** As needed (bug fixes)
- **Minor releases:** Every 1-2 months (new features)
- **Major releases:** Annually (breaking changes)

### Versioning Strategy
- **Semantic versioning:** major.minor.patch
- **PR labels for bumps:**
  - `release:major` - Breaking changes
  - `release:minor` - New features
  - `release:patch` - Bug fixes (default)

---

## Success Metrics

### Adoption Metrics (Current)
- **GitHub Stars:** ~50 (target: 100 by Q2 2025)
- **Releases Downloaded:** ~300 (target: 500 by Q2 2025)
- **Active Users:** ~150 (estimated from update checks)

### Quality Metrics (Current)
- **Crash Rate:** <0.1%
- **False Alarm Rate:** <0.1%
- **Missed Alarm Rate:** 0%
- **Update Adoption:** ~70% within 7 days (target: >80%)

### User Satisfaction (Target)
- **GitHub Issues:** <5 open bugs
- **Feature Requests:** Respond within 7 days
- **User Feedback:** >80% positive tone in issues/discussions

---

## Risks & Mitigation

### Technical Risks
| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| UpdateManager memory leak causes crashes | Medium | High | Fix in v1.4.0, recommend periodic restarts |
| macOS API changes break functionality | Low | High | Monitor Apple beta releases, update promptly |
| Accessibility API restrictions | Low | Critical | Diversify detection methods (camera, sound) |

### Business Risks
| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Solo developer bandwidth limits | High | Medium | Focus on core features, reject scope creep |
| Competition from commercial apps | Low | Low | Emphasize open-source, privacy, simplicity |
| Apple policy changes (Gatekeeper) | Medium | Medium | Obtain Developer ID, notarize app |

---

## Contributing

### How to Contribute
1. Fork the repository
2. Create a feature branch (`feature/your-feature`)
3. Implement changes with tests
4. Submit pull request with clear description
5. Label PR with `release:major`, `release:minor`, or `release:patch`

### Contribution Areas
- 🐛 **Bug fixes** - Always welcome
- ✨ **New features** - Discuss in issue first
- 📚 **Documentation** - Improvements and clarifications
- 🧪 **Tests** - Increase coverage
- 🎨 **UI/UX** - Design improvements

---

## Appendix

### Release History
| Version | Date | Highlights |
|---------|------|------------|
| v1.4.0 | 2025-12-24 | Multiple trusted devices (up to 10) |
| v1.3.4 | 2025-12-19 | Comprehensive documentation |
| v1.3.3 | 2024-12-18 | CI/CD automation complete |
| v1.3.0 | 2024-12-18 | GitHub Actions workflow |
| v1.2.0 | 2024-12-15 | Sparkle auto-update |
| v1.1.0 | 2024-11-20 | Bluetooth proximity |
| v1.0.0 | 2024-10-01 | Initial release |

### References
- [GitHub Repository](https://github.com/shenglong209/MacGuard)
- [GitHub Releases](https://github.com/shenglong209/MacGuard/releases)
- [GitHub Issues](https://github.com/shenglong209/MacGuard/issues)
- [Sparkle Documentation](https://sparkle-project.org/documentation/)
