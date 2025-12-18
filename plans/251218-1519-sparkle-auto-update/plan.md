# Sparkle Auto-Update Implementation Plan

**Project:** MacGuard
**Date:** 2025-12-18
**Version:** 1.2.0 (target)

---

## Overview

Implement Sparkle 2.x framework for automatic and manual update checking in MacGuard menu bar app. User preference: Auto + Manual checking via Settings UI.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                     MacGuardApp                          │
│  ┌───────────────────────────────────────────────────┐  │
│  │          SPUStandardUpdaterController             │  │
│  │  - startingUpdater: true (auto-check enabled)     │  │
│  │  - checkForUpdates() for manual trigger           │  │
│  └───────────────────────────────────────────────────┘  │
│                           │                              │
│              ┌────────────┴────────────┐                │
│              ▼                         ▼                │
│      SettingsView               MenuBarView             │
│   (Check for Updates)       (future: update badge)      │
└─────────────────────────────────────────────────────────┘
                              │
                              ▼
                    GitHub (appcast.xml)
                    https://raw.githubusercontent.com/
                    shenglong209/MacGuard/main/appcast.xml
```

## Integration Points

| File | Change |
|------|--------|
| `Package.swift` | Add Sparkle dependency |
| `MacGuardApp.swift` | Initialize SPUStandardUpdaterController |
| `Views/SettingsView.swift` | Add "Check for Updates" button in About section |
| `Info.plist` | Add SUFeedURL, SUPublicEDKey, update CFBundleVersion |
| `appcast.xml` (new) | Update feed at repo root |
| `scripts/release.sh` (new) | Automate signing and appcast generation |

## Phases

### Phase 1: SPM Integration & Key Setup
**File:** `phase-01-spm-integration.md`

### Phase 2: App Code Integration
**File:** `phase-02-app-integration.md`

### Phase 3: Release Automation
**File:** `phase-03-release-automation.md`

## Technical Decisions

1. **SPM over CocoaPods/Carthage** - Native Swift package support, simpler integration
2. **GitHub raw URL for appcast** - Free hosting, versioned with repo
3. **EdDSA signing** - Mandatory in Sparkle 2.x, more secure than DSA
4. **Auto-check enabled by default** - User expectation for security app

## Testing Strategy

1. Build with Sparkle dependency - verify compilation
2. Test manual "Check for Updates" button works
3. Create test release with higher version - verify update flow
4. Test LSUIElement behavior - update dialogs appear correctly
5. Verify signing workflow - signature validation passes

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| EdDSA key loss | Export to secure backup immediately after generation |
| Update UI hidden (LSUIElement) | Test on clean system, dialogs should float |
| Build failure with SPM | Verify Sparkle 2.x macOS 13+ compatibility |

## Dependencies

- Sparkle 2.x (latest stable)
- Xcode 15+ (for SPM)
- macOS 13.0+ (already required)

## Success Criteria

- [x] App builds with Sparkle framework
- [x] "Check for Updates" button in Settings works
- [ ] Automatic update check on 2nd launch (runtime testing required)
- [x] EdDSA-signed DMG passes verification
- [x] appcast.xml hosted and accessible
- [ ] End-to-end update flow tested

**Phase 1 Status:** ✅ COMPLETE (2025-12-18 15:44)
**Phase 2 Status:** ✅ COMPLETE (2025-12-18 16:04)
**Phase 3 Status:** ✅ COMPLETE (2025-12-18 16:22)

---

## Implementation Order

1. Phase 1 first (setup foundation)
2. Phase 2 (code changes)
3. Phase 3 (automation - can be deferred to first actual release)

**Estimated complexity:** Medium - straightforward SPM integration, main work is release automation.
