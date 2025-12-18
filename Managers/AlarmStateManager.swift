// AlarmStateManager.swift
// MacGuard - Anti-Theft Alarm for macOS
// Created: 2025-12-18

import SwiftUI
import Combine
import CoreBluetooth

/// Central state machine managing alarm states and transitions
@MainActor
class AlarmStateManager: ObservableObject {
    // MARK: - Published Properties

    @Published private(set) var state: AlarmState = .idle
    @Published var countdownSeconds: Int = 3
    @Published var hasAccessibilityPermission = false

    // MARK: - Configuration

    private let countdownDuration = 3

    // MARK: - Public Managers (for UI access)

    let bluetoothManager = BluetoothProximityManager()
    let authManager = AuthManager()
    let audioManager = AlarmAudioManager()

    // MARK: - Private Properties

    private var countdownTimer: Timer?
    private var permissionCheckTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let inputMonitor = InputMonitor()
    private let sleepMonitor = SleepMonitor()
    private let powerMonitor = PowerMonitor()
    private let overlayController = CountdownWindowController()

    // MARK: - Computed Properties

    var isArmed: Bool {
        state != .idle
    }

    // MARK: - Initialization

    init() {
        inputMonitor.delegate = self
        sleepMonitor.delegate = self
        powerMonitor.delegate = self
        bluetoothManager.delegate = self
        checkPermissions()
        startPermissionPolling()

        // Forward bluetoothManager changes to trigger view updates
        bluetoothManager.$trustedDevice
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    /// Check current accessibility permission status
    func checkPermissions() {
        hasAccessibilityPermission = InputMonitor.hasAccessibilityPermission()
        // Stop polling once permission is granted
        if hasAccessibilityPermission {
            stopPermissionPolling()
        }
    }

    /// Start polling for permission changes (when permission not yet granted)
    private func startPermissionPolling() {
        guard !hasAccessibilityPermission else { return }
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkPermissions()
            }
        }
    }

    /// Stop permission polling
    private func stopPermissionPolling() {
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = nil
    }

    /// Request accessibility permission from user
    func requestAccessibilityPermission() {
        InputMonitor.requestAccessibilityPermission()
        // Start polling for permission changes (user may grant in System Preferences)
        startPermissionPolling()
    }

    // MARK: - State Transitions

    /// Arm the alarm system, optionally lock screen, and start monitoring
    func arm() {
        guard state == .idle else { return }

        // Pre-load audio for instant playback
        audioManager.prepare()

        // Lock screen if enabled in settings
        if AppSettings.shared.autoLockOnArm {
            lockScreen()
        }

        // Start monitors after a delay to avoid capturing the lock keystroke
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }

            // Start input monitoring
            guard self.inputMonitor.startMonitoring() else {
                // Permission denied - show warning
                self.hasAccessibilityPermission = false
                return
            }

            // Start system event monitors
            self.sleepMonitor.startMonitoring()
            self.powerMonitor.startMonitoring()

            // Start Bluetooth proximity scanning
            self.bluetoothManager.startScanning()

            self.hasAccessibilityPermission = true
            self.state = .armed
            print("[MacGuard] Armed - monitoring active")
        }
    }

    /// Lock the Mac screen
    private func lockScreen() {
        // Primary method: pmset displaysleepnow (reliable on modern macOS)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        task.arguments = ["displaysleepnow"]

        do {
            try task.run()
            task.waitUntilExit()
            print("[MacGuard] Screen locked via pmset")
        } catch {
            print("[MacGuard] Failed to lock via pmset: \(error)")
            // Fallback: AppleScript
            lockScreenViaAppleScript()
        }
    }

    private func lockScreenViaAppleScript() {
        let script = """
        tell application "System Events" to keystroke "q" using {control down, command down}
        """
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            scriptObject.executeAndReturnError(&error)
            if error == nil {
                print("[MacGuard] Screen locked via AppleScript")
            }
        }
    }

    /// Disarm the alarm system, stop all monitoring
    func disarm() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        inputMonitor.stopMonitoring()
        sleepMonitor.stopMonitoring()
        powerMonitor.stopMonitoring()
        bluetoothManager.stopScanning()

        // Stop audio, release pre-loaded audio, and hide overlay
        audioManager.stopAlarm()
        audioManager.unprepare()
        overlayController.hide()

        state = .idle
        print("[MacGuard] Disarmed")
    }

    /// Attempt to disarm with biometric authentication
    /// - Parameter completion: Called with success status
    func attemptBiometricDisarm(completion: @escaping (Bool) -> Void) {
        authManager.authenticateWithBiometrics { [weak self] success, error in
            if success {
                self?.disarm()
            }
            completion(success)
        }
    }

    /// Attempt to disarm with PIN
    /// - Parameter pin: The entered PIN
    /// - Returns: true if PIN is correct and alarm is disarmed
    func attemptPINDisarm(_ pin: String) -> Bool {
        if authManager.validatePIN(pin) {
            disarm()
            return true
        }
        return false
    }

    /// Trigger the alarm countdown (called when intrusion detected)
    func trigger() {
        guard state == .armed else { return }

        // Check if trusted device is nearby - if so, don't trigger
        if bluetoothManager.isTrustedDeviceNearby() {
            print("[MacGuard] Trusted device nearby - ignoring trigger")
            return
        }

        state = .triggered
        countdownSeconds = countdownDuration

        // Show fullscreen overlay
        overlayController.show(alarmManager: self)

        startCountdown()
        print("[MacGuard] Triggered - countdown started")
    }

    /// Immediately trigger alarm (e.g., for lid close)
    func triggerImmediate() {
        guard state == .armed || state == .triggered else { return }

        // Even for immediate triggers, check Bluetooth proximity
        if bluetoothManager.isTrustedDeviceNearby() {
            print("[MacGuard] Trusted device nearby - ignoring immediate trigger")
            return
        }

        countdownTimer?.invalidate()
        countdownTimer = nil

        // Show overlay and start alarm
        overlayController.show(alarmManager: self)
        audioManager.playAlarm()

        state = .alarming
        print("[MacGuard] ALARM ACTIVE")
    }

    // MARK: - Private Methods

    private func startCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.countdownSeconds -= 1
                if self.countdownSeconds <= 0 {
                    self.countdownTimer?.invalidate()
                    self.countdownTimer = nil

                    // Start alarm
                    self.audioManager.playAlarm()
                    self.state = .alarming
                    print("[MacGuard] Countdown expired - ALARM ACTIVE")
                }
            }
        }
    }
}

// MARK: - InputMonitorDelegate

extension AlarmStateManager: InputMonitorDelegate {
    nonisolated func inputDetected(eventType: CGEventType) {
        Task { @MainActor in
            guard self.state == .armed else { return }

            // Log event type for debugging
            let eventName: String
            switch eventType {
            case .keyDown: eventName = "keyboard"
            case .leftMouseDown, .rightMouseDown, .otherMouseDown: eventName = "mouse click"
            case .mouseMoved: eventName = "mouse move"
            case .scrollWheel: eventName = "scroll/touchpad"
            default: eventName = "unknown"
            }
            print("[MacGuard] Input detected: \(eventName)")

            self.trigger()
        }
    }
}

// MARK: - SleepMonitorDelegate

extension AlarmStateManager: SleepMonitorDelegate {
    nonisolated func lidWillClose() {
        Task { @MainActor in
            guard self.state == .armed else { return }
            // Lid close = immediate alarm (no countdown per validation)
            print("[MacGuard] Lid close detected - immediate alarm")
            self.triggerImmediate()
        }
    }

    nonisolated func systemDidWake() {
        Task { @MainActor in
            // Auto-disarm if trusted device is nearby on wake
            if self.bluetoothManager.isTrustedDeviceNearby() {
                print("[MacGuard] System woke - trusted device nearby, auto-disarming")
                self.disarm()
            } else {
                print("[MacGuard] System woke from sleep")
            }
        }
    }
}

// MARK: - PowerMonitorDelegate

extension AlarmStateManager: PowerMonitorDelegate {
    nonisolated func powerCableDisconnected() {
        Task { @MainActor in
            guard self.state == .armed else { return }
            // Power disconnect = start countdown
            print("[MacGuard] Power cable disconnected - starting countdown")
            self.trigger()
        }
    }

    nonisolated func powerCableConnected() {
        // No action needed
    }
}

// MARK: - BluetoothProximityDelegate

extension AlarmStateManager: BluetoothProximityDelegate {
    nonisolated func trustedDeviceNearby(_ device: TrustedDevice) {
        Task { @MainActor in
            // Auto-disarm if in triggered or alarming state
            if self.state == .triggered || self.state == .alarming {
                print("[MacGuard] Trusted device detected - auto-disarming")
                self.disarm()
            }
        }
    }

    nonisolated func trustedDeviceAway(_ device: TrustedDevice) {
        // No automatic action when device leaves
        print("[MacGuard] Trusted device left proximity")
    }

    nonisolated func bluetoothStateChanged(_ state: CBManagerState) {
        if state == .poweredOff {
            print("[MacGuard] Bluetooth turned off")
        }
    }
}
