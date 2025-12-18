# Sparkle 2.x Framework Integration Research

**Date:** 2025-12-18
**Focus:** Swift Package Manager integration, SwiftUI compatibility, Info.plist config, LSUIElement considerations, update mechanisms

---

## 1. Swift Package Manager Integration

### Installation Steps
```
1. Xcode → File → Add Packages…
2. Repository URL: https://github.com/sparkle-project/Sparkle
3. Accept default package options (auto-updates enabled)
4. Tools location: Right-click Sparkle in project navigator → Show in Finder
   Path: ../artifacts/sparkle/Sparkle/bin/
```

### Key Tools
- `generate_keys` - Creates EdDSA keypair (private → Keychain, public → Info.plist)
- `sign_update` - Signs update archives for distribution

---

## 2. SwiftUI Compatibility & SPUStandardUpdaterController

### Basic Setup (SwiftUI App)

```swift
import Sparkle

@main
struct MacGuardApp: App {
    private let updaterController: SPUStandardUpdaterController

    init() {
        // Initialize updater - starts automatically if startingUpdater: true
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
        }
    }
}
```

### Menu Bar App Integration (SwiftUI)

```swift
@main
struct MenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let updaterController: SPUStandardUpdaterController

    override init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let menu = NSMenu()
        menu.addItem(NSMenuItem(
            title: "Check for Updates…",
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        ))
        statusItem?.menu = menu
    }

    @objc func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
```

### SwiftUI Check Updates View with State Binding

```swift
final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}

struct CheckForUpdatesView: View {
    @ObservedObject private var viewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        self.viewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("Check for Updates…", action: updater.checkForUpdates)
            .disabled(!viewModel.canCheckForUpdates)
    }
}
```

---

## 3. Info.plist Configuration

### Required Keys
```xml
<key>SUFeedURL</key>
<string>https://example.com/appcast.xml</string>

<key>SUPublicEDKey</key>
<string>YOUR_BASE64_ENCODED_PUBLIC_KEY</string>
```

### Automatic Update Control
```xml
<!-- Enable/disable automatic checks -->
<key>SUEnableAutomaticChecks</key>
<true/>  <!-- YES: auto-enable, NO: disable, omit: prompt user on 2nd launch -->

<!-- Check interval (seconds, min 3600, default 86400) -->
<key>SUScheduledCheckInterval</key>
<integer>86400</integer>

<!-- Silent background updates (default NO) -->
<key>SUAutomaticallyUpdate</key>
<true/>

<!-- Allow users to enable automatic updates (default YES) -->
<key>SUAllowsAutomaticUpdates</key>
<true/>
```

### Additional Settings
```xml
<!-- Verify update before extraction (Sparkle 2.7+) -->
<key>SUVerifyUpdateBeforeExtraction</key>
<true/>

<!-- Show release notes (default YES) -->
<key>SUShowReleaseNotes</key>
<true/>

<!-- Enable system profiling (default NO) -->
<key>SUEnableSystemProfiling</key>
<false/>
```

### Sandboxing (if needed)
```xml
<key>SUEnableInstallerLauncherService</key>
<true/>  <!-- Required for sandboxed apps -->

<key>SUEnableDownloaderService</key>
<true/>  <!-- If app lacks network entitlement -->
```

---

## 4. LSUIElement (Menu Bar App) Considerations

**Official Documentation:** No specific LSUIElement guidance found in Sparkle docs.

### Known Behaviors
- Sparkle works with `LSUIElement=true` apps
- Update UI appears as floating windows (no dock icon needed)
- First launch check skipped (check happens on 2nd launch by default)

### Testing Update Timing
```bash
# Clear last check time to trigger immediate check
defaults delete com.yourapp.bundleid SULastCheckTime
```

### Potential Issues
- Update dialogs may lack app context if dock icon hidden
- Users might miss update notifications without dock presence
- Consider more prominent update prompts in menu bar UI

---

## 5. Programmatic vs Automatic Update Checking

### Automatic (Default Behavior)
- **No code required** after initialization with `startingUpdater: true`
- Checks every 24 hours (configurable via `SUScheduledCheckInterval`)
- First check on **2nd launch**, not first launch
- Runs in background via `checkForUpdatesInBackground()`

### Programmatic Checking

**Manual User-Triggered Check:**
```swift
updaterController.checkForUpdates(nil)
```

**Check Update Availability:**
```swift
let canCheck = updaterController.updater.canCheckForUpdates
```

**Reset Update Cycle (after settings change):**
```swift
updaterController.updater.resetUpdateCycleAfterShortDelay()
```

### Best Practices
- **DO NOT** call `checkForUpdatesInBackground()` manually - Sparkle handles this
- **DO** use `checkForUpdates()` for user-initiated checks (menu items)
- **DO** call `resetUpdateCycleAfterShortDelay()` when users change feed URLs
- **DO** configure settings in Info.plist, not programmatically

### Delegate Customization

```swift
class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        // Dynamic feed URL if not in Info.plist
        return "https://example.com/appcast.xml"
    }

    func updater(_ updater: SPUUpdater,
                 willScheduleUpdateCheckAfterDelay delay: TimeInterval) {
        // Called before automatic background check
    }
}

// Initialize with delegate
updaterController = SPUStandardUpdaterController(
    startingUpdater: true,
    updaterDelegate: UpdaterDelegate(),
    userDriverDelegate: nil
)
```

---

## Summary

**SPM Integration:** Single-step Xcode package addition, tools in artifacts folder.

**SwiftUI:** Full support via `SPUStandardUpdaterController`, initialize in App struct, use `@NSApplicationDelegateAdaptor` for menu bar apps.

**Info.plist:** Requires `SUFeedURL` + `SUPublicEDKey` minimum, extensive customization via `SU*` keys.

**LSUIElement:** Works but no official docs - update UI floats, test with cleared defaults, consider UX for dock-less apps.

**Update Modes:** Automatic default (24hr), programmatic for user-triggered checks, avoid manual background calls.

---

## Unresolved Questions

1. Best practices for LSUIElement update notifications (in-menu vs dialog)?
2. Recommended approach for beta channel switching in menu bar apps?
3. Performance impact of `SUAutomaticallyUpdate` on menu bar apps?
