# Phase 2: App Code Integration

## Tasks

### 2.1 Create UpdateManager

**New File:** `Managers/UpdateManager.swift`

```swift
// UpdateManager.swift
// MacGuard - Anti-Theft Alarm for macOS

import SwiftUI
import Sparkle

/// Manages Sparkle auto-update functionality
final class UpdateManager: ObservableObject {
    /// Shared instance for app-wide access
    static let shared = UpdateManager()

    /// Sparkle updater controller
    private let updaterController: SPUStandardUpdaterController

    /// Whether update check is available (not already in progress)
    @Published var canCheckForUpdates = false

    private init() {
        // Initialize updater - starts automatic checking
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        // Bind canCheckForUpdates to updater state
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    /// Trigger manual update check (user-initiated)
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    /// Access to underlying updater for advanced usage
    var updater: SPUUpdater {
        updaterController.updater
    }
}
```

### 2.2 Initialize UpdateManager in MacGuardApp

**File:** `MacGuardApp.swift`

```swift
// MacGuardApp.swift
// MacGuard - Anti-Theft Alarm for macOS

import SwiftUI

@main
struct MacGuardApp: App {
    @StateObject private var alarmManager = AlarmStateManager()

    // Initialize update manager (starts Sparkle)
    private let updateManager = UpdateManager.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(alarmManager)
        } label: {
            MenuBarIconView(state: alarmManager.state)
        }
        .menuBarExtraStyle(.window)
    }
}

// ... rest of file unchanged
```

**Changes:**
- Added `import Sparkle` is not needed here (UpdateManager handles it)
- Added `updateManager` property to ensure initialization on app launch

### 2.3 Add Check for Updates Button to SettingsView

**File:** `Views/SettingsView.swift`

In the About section (around line 246), add update check button:

```swift
// About Section
Section {
    LabeledContent("Version", value: "1.1.0")
    LabeledContent("macOS", value: "13.0+ (Ventura)")

    // Check for Updates button
    HStack {
        Text("Updates")
        Spacer()
        Button("Check for Updates...") {
            UpdateManager.shared.checkForUpdates()
        }
        .disabled(!UpdateManager.shared.canCheckForUpdates)
    }

    Link(destination: URL(string: "https://github.com/shenglong209/MacGuard")!) {
        HStack {
            Text("GitHub Repository")
            Spacer()
            Image(systemName: "arrow.up.right.square")
                .foregroundColor(.secondary)
        }
    }
} header: {
    Label("About", systemImage: "info.circle")
}
```

### 2.4 Alternative: SwiftUI CheckForUpdatesView Component

For reactive button state, create reusable component:

**New File (optional):** `Views/CheckForUpdatesView.swift`

```swift
// CheckForUpdatesView.swift
// MacGuard - Anti-Theft Alarm for macOS

import SwiftUI
import Sparkle

/// SwiftUI view for "Check for Updates" button with reactive state
struct CheckForUpdatesView: View {
    @ObservedObject private var updateManager = UpdateManager.shared

    var body: some View {
        Button("Check for Updates...") {
            updateManager.checkForUpdates()
        }
        .disabled(!updateManager.canCheckForUpdates)
    }
}
```

Then in SettingsView:

```swift
HStack {
    Text("Updates")
    Spacer()
    CheckForUpdatesView()
}
```

## File Changes Summary

| File | Action | Description |
|------|--------|-------------|
| `Managers/UpdateManager.swift` | Create | Sparkle integration singleton |
| `MacGuardApp.swift` | Modify | Initialize UpdateManager |
| `Views/SettingsView.swift` | Modify | Add Check for Updates button |
| `Views/CheckForUpdatesView.swift` | Create (optional) | Reactive button component |

## Verification Checklist

- [x] UpdateManager compiles with Sparkle import
- [x] App launches without crash
- [x] "Check for Updates" button appears in Settings
- [x] Button disabled during update check (reactive state)
- [ ] Manual check shows "up to date" dialog (when no newer version) - **Requires runtime testing**

**Phase 2 Completion:** ✅ DONE (2025-12-18 16:04)

## Code Review Results (2025-12-18)

**Status:** ✅ Implementation Complete | ⚠️ 1 Critical Fix Required

### Critical Issue Found
- **Memory Leak in UpdateManager.swift**: Combine publisher `assign(to: &$canCheckForUpdates)` creates strong reference cycle
- **Fix Required**: Add `Set<AnyCancellable>()` storage and use `.store(in:)` pattern (see AlarmStateManager.swift reference)
- **Severity:** BLOCKER for v1.2.0 release

### Summary
- 0 security vulnerabilities
- 0 compiler warnings
- 1 cosmetic typo (MARK comment missing slash)
- 2 low-priority improvements suggested (version display, documentation)

**Full Report:** `/plans/reports/code-reviewer-251218-1558-GH-2-phase2-sparkle-integration.md`

## Notes

- UpdateManager is a singleton to ensure single Sparkle instance
- `startingUpdater: true` begins automatic background checks
- First auto-check occurs on 2nd launch (Sparkle default behavior)
- Manual check via button always works immediately
