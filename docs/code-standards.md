# MacGuard Code Standards

**Version:** 1.3.4
**Last Updated:** 2025-12-19
**Language:** Swift 5.9+

## Architecture & Design Patterns

### 1. State Machine Pattern
**Implementation:** AlarmStateManager.swift

The core of MacGuard is a state machine with four states:
```swift
enum AlarmState {
    case idle       // Disarmed, not monitoring
    case armed      // Monitoring input, sleep, power
    case triggered  // 3-second countdown active
    case alarming   // Loud alarm playing
}
```

**Principles:**
- Single source of truth for alarm state
- Atomic state transitions (no race conditions)
- Observable state changes via Combine (@Published)
- Delegates coordinate with state manager

**State Transition Rules:**
```
idle → armed (user arms)
armed → triggered (input/sleep/power event)
triggered → alarming (countdown expires)
triggered → armed (user authenticates during countdown)
alarming → idle (user authenticates)
armed → idle (user disarms or Bluetooth proximity)
```

### 2. Delegate Pattern
**Implementation:** All monitors → AlarmStateManager

Monitors use delegate protocols to communicate events:

```swift
protocol InputMonitorDelegate: AnyObject {
    func inputMonitorDidDetectInput()
}

protocol SleepMonitorDelegate: AnyObject {
    func sleepMonitorDidDetectLidClose()
}

// Similar patterns for PowerMonitor, BluetoothProximityManager
```

**Principles:**
- Weak delegate references (avoid retain cycles)
- Single responsibility per monitor
- Clear, descriptive delegate method names
- Delegates are always weak references

### 3. Singleton Pattern
**Implementation:** Managers and window controllers

Used for globally accessible state and resources:
- `AlarmStateManager.shared`
- `CountdownWindowController.shared`
- `SettingsWindowController.shared`

**Justification:**
- Single instance required (one alarm state, one overlay window)
- Global access needed from multiple views
- Thread-safe via DispatchQueue synchronization

**Caution:**
- Avoid overuse (only when truly global state)
- Consider dependency injection for testability
- Document why singleton is necessary

### 4. Observer Pattern
**Implementation:** Combine framework

Reactive state updates via @Published:
```swift
class AlarmStateManager: ObservableObject {
    @Published var currentState: AlarmState = .idle
    @Published var countdownSeconds: Int = 3
}
```

Views observe changes:
```swift
struct MenuBarView: View {
    @ObservedObject var stateManager = AlarmStateManager.shared

    var body: some View {
        // UI automatically updates when currentState changes
    }
}
```

**Principles:**
- Use @Published for mutable state
- Use @ObservedObject or @StateObject in views
- Minimize published properties (only observable state)

### 5. Protocol-Oriented Design
**Implementation:** Throughout codebase

Prefer protocols over concrete inheritance:
```swift
protocol AudioPlayable {
    func play()
    func stop()
}

class AlarmAudioManager: AudioPlayable {
    // Implementation
}
```

**Benefits:**
- Testability (mock implementations)
- Flexibility (swap implementations)
- Clear contracts (explicit requirements)

## Naming Conventions

### Files
- **Managers:** `{Purpose}Manager.swift` (e.g., AlarmStateManager, AuthManager)
- **Models:** `{Entity}.swift` (e.g., AlarmState, TrustedDevice)
- **Views:** `{Component}View.swift` (e.g., MenuBarView, SettingsView)
- **Controllers:** `{Component}WindowController.swift` (e.g., CountdownWindowController)

### Classes & Structs
- **PascalCase:** `AlarmStateManager`, `TrustedDevice`
- **Descriptive names:** Prefer `BluetoothProximityManager` over `BTPManager`
- **Avoid abbreviations:** Exception: RSSI, PIN (industry standard)

### Functions & Methods
- **camelCase:** `armAlarm()`, `triggerCountdown()`
- **Verb-first:** `detectInput()`, `playAlarm()`, `stopMonitoring()`
- **Delegate methods:** Prefix with delegate type
  ```swift
  func inputMonitorDidDetectInput()
  func sleepMonitorDidDetectLidClose()
  ```

### Properties
- **camelCase:** `currentState`, `countdownSeconds`, `trustedDeviceUUID`
- **Boolean prefix:** `is`, `has`, `should`
  ```swift
  var isArmed: Bool
  var hasAccessibilityPermission: Bool
  var shouldAutoLock: Bool
  ```

### Constants
- **camelCase:** `rssiThreshold`, `countdownDuration`
- **Static constants:** Use static let in structs
  ```swift
  struct Constants {
      static let rssiThreshold: Double = -60.0
      static let countdownDuration: Int = 3
  }
  ```

### Enums
- **PascalCase enum name:** `AlarmState`
- **camelCase cases:** `idle`, `armed`, `triggered`, `alarming`

## Code Organization

### File Structure
1. **Import statements** (grouped by framework)
2. **Type definition** (class/struct/enum)
3. **Properties** (published, private, computed)
4. **Initializers**
5. **Public methods**
6. **Private methods**
7. **Extensions** (protocol conformances)

Example:
```swift
import SwiftUI
import Combine
import LocalAuthentication

class AuthManager: ObservableObject {
    // MARK: - Published Properties
    @Published var isAuthenticated: Bool = false

    // MARK: - Private Properties
    private let context = LAContext()

    // MARK: - Initialization
    init() {
        // Setup
    }

    // MARK: - Public Methods
    func authenticateWithTouchID() {
        // Implementation
    }

    // MARK: - Private Methods
    private func savePIN(_ pin: String) {
        // Implementation
    }
}

// MARK: - PIN Management Extension
extension AuthManager {
    func setupPIN(_ pin: String) {
        // Implementation
    }
}
```

### Directory Structure
```
MacGuard/
├── Managers/          # Business logic and state management
├── Models/            # Data structures
├── Views/             # SwiftUI views
├── Utilities/         # Helper classes
└── Resources/         # Assets (icons, audio)
```

## Swift Style Guide

### Access Control
- **Default to private:** Expose only what's necessary
- **Use fileprivate sparingly:** Prefer private or internal
- **Public for shared state:** Published properties, shared singletons

```swift
class AlarmStateManager {
    public static let shared = AlarmStateManager()
    @Published public var currentState: AlarmState = .idle

    private var monitors: [Monitor] = []

    private init() { }  // Singleton pattern
}
```

### Optionals
- **Avoid force unwrapping:** Use `if let`, `guard let`, or `??`
- **Prefer optional chaining:** `device?.name ?? "Unknown"`
- **Use guard for early returns:**
  ```swift
  guard let device = selectedDevice else {
      print("No device selected")
      return
  }
  ```

### Error Handling
- **Use Result type for async operations:**
  ```swift
  func authenticate(completion: @escaping (Result<Void, AuthError>) -> Void) {
      // Implementation
  }
  ```
- **Descriptive error enums:**
  ```swift
  enum AuthError: Error {
      case touchIDFailed
      case pinIncorrect
      case noAuthMethodAvailable
  }
  ```
- **Log errors with context:**
  ```swift
  catch {
      print("Failed to save PIN to Keychain: \(error)")
  }
  ```

### SwiftUI Patterns

#### State Management
- **@StateObject for creation:** Views that create their own state
- **@ObservedObject for passing:** Views that receive state from parent
- **@EnvironmentObject for globals:** Shared state across view hierarchy

```swift
struct MenuBarView: View {
    @ObservedObject var stateManager = AlarmStateManager.shared
    @StateObject private var settings = AppSettings()

    var body: some View {
        // UI
    }
}
```

#### View Composition
- **Extract subviews for clarity:**
  ```swift
  struct SettingsView: View {
      var body: some View {
          VStack {
              PermissionsSection()
              DeviceSection()
              SecuritySection()
          }
      }
  }

  private struct PermissionsSection: View {
      var body: some View {
          // Implementation
      }
  }
  ```

#### Modifiers
- **Chain modifiers logically:**
  ```swift
  Text("Alarm Armed")
      .font(.headline)
      .foregroundColor(.red)
      .padding()
  ```

### Combine Patterns

#### Publishers
- **Use @Published for observable state:**
  ```swift
  @Published var currentState: AlarmState = .idle
  ```

#### Subscriptions
- **Store subscriptions in Set:**
  ```swift
  private var cancellables = Set<AnyCancellable>()

  stateManager.$currentState
      .sink { state in
          // Handle state change
      }
      .store(in: &cancellables)
  ```

#### Operators
- **Debounce for frequent updates:**
  ```swift
  rssiPublisher
      .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
      .sink { rssi in
          // Handle RSSI update
      }
  ```

## Threading & Concurrency

### Main Thread for UI
- **All UI updates on main thread:**
  ```swift
  DispatchQueue.main.async {
      self.currentState = .armed
  }
  ```

### Background Work
- **Use global queues for heavy work:**
  ```swift
  DispatchQueue.global(qos: .background).async {
      // Expensive computation
      DispatchQueue.main.async {
          // Update UI
      }
  }
  ```

### Synchronization
- **Use DispatchQueue for thread safety:**
  ```swift
  private let queue = DispatchQueue(label: "com.macguard.statemanager")

  func updateState(_ newState: AlarmState) {
      queue.sync {
          self.currentState = newState
      }
  }
  ```

## Resource Management

### Bundle Resources
- **Use ResourceBundle utility:**
  ```swift
  let bundle = ResourceBundle.bundle
  let soundURL = bundle.url(forResource: "dont-touch-my-mac", withExtension: "mp3")
  ```

### Memory Management
- **Weak references for delegates:**
  ```swift
  weak var delegate: InputMonitorDelegate?
  ```
- **Capture lists in closures:**
  ```swift
  timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
      self?.updateCountdown()
  }
  ```

### Cleanup
- **Deinit for resource cleanup:**
  ```swift
  deinit {
      stopMonitoring()
      cancellables.removeAll()
  }
  ```

## Permissions & Security

### Accessibility Permission
- **Check permission status:**
  ```swift
  let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true]
  let isEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary)
  ```

### Bluetooth Permission
- **Handle authorization states:**
  ```swift
  func centralManagerDidUpdateState(_ central: CBCentralManager) {
      switch central.authorization {
      case .allowedAlways:
          startScanning()
      case .denied, .restricted:
          print("Bluetooth permission denied")
      default:
          break
      }
  }
  ```

### Keychain Access
- **Use Security framework for PIN:**
  ```swift
  let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrAccount as String: "com.MacGuard.PIN",
      kSecValueData as String: pinData
  ]
  SecItemAdd(query as CFDictionary, nil)
  ```

## Testing Guidelines

### Unit Testing (Future)
- **Test state transitions:**
  ```swift
  func testArmingTransitionToTriggered() {
      let manager = AlarmStateManager()
      manager.arm()
      XCTAssertEqual(manager.currentState, .armed)

      manager.handleInput()
      XCTAssertEqual(manager.currentState, .triggered)
  }
  ```

### Manual Testing
- **Test all state transitions**
- **Test permission edge cases** (denied, revoked)
- **Test Bluetooth proximity edge cases** (out of range, device off)
- **Test audio playback** (different sounds, volume levels)

## Documentation Standards

### Inline Comments
- **Comment "why", not "what":**
  ```swift
  // Force volume to max to ensure alarm is audible
  setSystemVolume(1.0)
  ```

### Function Documentation
- **Use doc comments for public APIs:**
  ```swift
  /// Authenticates the user using Touch ID or PIN fallback.
  /// - Parameter completion: Callback with authentication result.
  func authenticate(completion: @escaping (Bool) -> Void) {
      // Implementation
  }
  ```

### Complex Logic
- **Add comments for non-obvious code:**
  ```swift
  // RSSI threshold of -60 dB provides ~5-10 meter range
  // Values vary by device type and environment
  let rssiThreshold: Double = -60.0
  ```

## Version Control

### Commit Messages
- **Format:** `type: subject`
- **Types:** feat, fix, chore, docs, refactor, test
- **Examples:**
  - `feat: add Bluetooth proximity auto-disarm`
  - `fix: prevent sleep when lid close alarm enabled`
  - `chore: update Sparkle to 2.6.0`
  - `docs: update README with installation instructions`

### Branching
- **main:** Production-ready code
- **feature/{name}:** New features
- **fix/{name}:** Bug fixes
- **chore/{name}:** Maintenance tasks

### Pull Requests
- **Label for version bumps:** `release:major`, `release:minor`, `release:patch`
- **Descriptive titles:** Summarize changes
- **Link to issues:** Reference GitHub issues if applicable

## Build & Distribution

### Build Configuration
- **Debug:** Development builds (`swift build`)
- **Release:** Distribution builds (`swift build -c release`)

### Code Signing
- **Optional but recommended:** Preserves Accessibility permission
- **Certificate:** Apple Development or Apple Developer ID
- **Entitlements:** App Sandbox disabled, Bluetooth enabled

### Versioning
- **Semantic versioning:** major.minor.patch
- **Info.plist keys:**
  - `CFBundleShortVersionString`: User-facing version (e.g., 1.3.4)
  - `CFBundleVersion`: Build number (e.g., 2)

## Performance Best Practices

### Minimize State Updates
- **Batch updates when possible:**
  ```swift
  // Bad: Multiple updates
  self.currentState = .armed
  self.countdownSeconds = 3

  // Good: Single update
  updateState(armed: true, countdown: 3)
  ```

### Lazy Initialization
- **Initialize heavy resources on demand:**
  ```swift
  private lazy var audioPlayer: AVAudioPlayer? = {
      // Setup audio player
  }()
  ```

### Efficient Bluetooth Scanning
- **Stop scanning when idle:**
  ```swift
  func stopMonitoring() {
      centralManager?.stopScan()
  }
  ```

## Known Anti-Patterns to Avoid

### ❌ Retain Cycles
```swift
// Bad
timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
    self.updateCountdown()  // Strong reference to self
}

// Good
timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
    self?.updateCountdown()
}
```

### ❌ Force Unwrapping
```swift
// Bad
let device = devices.first!  // Crash if empty

// Good
guard let device = devices.first else {
    print("No devices found")
    return
}
```

### ❌ Main Thread Blocking
```swift
// Bad
DispatchQueue.main.async {
    let data = expensiveComputation()  // Blocks UI
    updateUI(data)
}

// Good
DispatchQueue.global(qos: .background).async {
    let data = expensiveComputation()
    DispatchQueue.main.async {
        updateUI(data)
    }
}
```

### ❌ Massive View Controllers
```swift
// Bad: 575-line SettingsView with inline sections

// Good: Extract subviews
struct SettingsView: View {
    var body: some View {
        PermissionsSection()
        DeviceSection()
        SecuritySection()
    }
}
```

## Tools & Linting

### Recommended Tools
- **SwiftLint:** Enforce code style (future integration)
- **SwiftFormat:** Auto-format code (future integration)
- **Xcode Instruments:** Profile performance and memory

### Current Status
- No automated linting (manual code review)
- No formatter (consistent style maintained manually)
- No unit tests (future roadmap item)

## Future Improvements

### Code Quality
- Add SwiftLint configuration
- Implement unit tests (target: >80% coverage)
- Add integration tests for state transitions
- Fix UpdateManager memory leak

### Architecture
- Refactor SettingsView into smaller components
- Consider dependency injection for testability
- Extract constants into dedicated Constants.swift file

### Documentation
- Add inline documentation for all public APIs
- Create architecture decision records (ADRs)
- Document known issues and workarounds
