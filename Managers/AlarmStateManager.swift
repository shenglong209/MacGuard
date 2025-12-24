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

    // MARK: - Public Managers (for UI access)

    let bluetoothManager = BluetoothProximityManager()
    let authManager = AuthManager()
    let audioManager = AlarmAudioManager()

    // MARK: - Private Properties

    private var countdownTimer: Timer?
    private var permissionCheckTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var autoArmTimer: Timer?
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
        bluetoothManager.$trustedDevices
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Observe AppSettings changes to start/stop scanning when auto-arm setting changes
        AppSettings.shared.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.handleSettingsChanged()
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
            guard let strongSelf = self else { return }
            Task { @MainActor in
                strongSelf.checkPermissions()
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
                ActivityLogManager.shared.log(.system, "Failed to arm - accessibility permission denied")
                return
            }

            // Start system event monitors
            self.sleepMonitor.startMonitoring()
            self.powerMonitor.startMonitoring()

            // Start Bluetooth proximity scanning
            self.bluetoothManager.startScanning()
            self.bluetoothManager.setArmedState(true)

            self.hasAccessibilityPermission = true
            self.state = .armed
            ActivityLogManager.shared.log(.armed, "System armed - monitoring active")
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
            ActivityLogManager.shared.log(.system, "Screen locked via pmset")
        } catch {
            ActivityLogManager.shared.log(.system, "Failed to lock via pmset: \(error)")
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
                ActivityLogManager.shared.log(.system, "Screen locked via AppleScript")
            }
        }
    }

    /// Disarm the alarm system, stop all monitoring
    /// - Parameter reason: Optional reason for disarming (logged to activity log)
    func disarm(reason: String? = nil) {
        countdownTimer?.invalidate()
        countdownTimer = nil
        cancelAutoArmTimer()
        inputMonitor.stopMonitoring()
        sleepMonitor.stopMonitoring()
        powerMonitor.stopMonitoring()
        bluetoothManager.setArmedState(false)
        bluetoothManager.stopScanning()

        // Stop audio, release pre-loaded audio, and hide overlay
        audioManager.stopAlarm()
        audioManager.unprepare()
        overlayController.hide()

        state = .idle
        ActivityLogManager.shared.log(.disarmed, reason ?? "System disarmed")

        // Only scan in idle if auto-arm enabled AND trusted devices configured
        // This reduces CPU from ~10% to <1% when feature is OFF (default)
        if AppSettings.shared.autoArmOnDeviceLeave,
           !bluetoothManager.trustedDevices.isEmpty {
            bluetoothManager.startScanning()
        }
    }

    /// Attempt to disarm with biometric authentication
    /// - Parameter completion: Called with success status
    func attemptBiometricDisarm(completion: @escaping (Bool) -> Void) {
        authManager.authenticateWithBiometrics { [weak self] success, error in
            if success {
                self?.disarm(reason: "Disarmed via Touch ID")
            }
            completion(success)
        }
    }

    /// Attempt to disarm with PIN
    /// - Parameter pin: The entered PIN
    /// - Returns: true if PIN is correct and alarm is disarmed
    func attemptPINDisarm(_ pin: String) -> Bool {
        if authManager.validatePIN(pin) {
            disarm(reason: "Disarmed via PIN")
            return true
        }
        return false
    }

    /// Trigger the alarm countdown (called when intrusion detected)
    func trigger() {
        guard state == .armed else { return }

        // Check if trusted device is nearby - behavior depends on auto-arm mode
        if bluetoothManager.isTrustedDeviceNearby() {
            // In "all devices away" mode: any nearby device suppresses trigger
            // In "any device away" mode: don't suppress - user explicitly wants alarm when any device is away
            if AppSettings.shared.autoArmMode == .allDevicesAway {
                ActivityLogManager.shared.log(.bluetooth, "Trusted device nearby - ignoring trigger")
                return
            }
            // "Any device away" mode: continue with trigger even if some devices are nearby
            ActivityLogManager.shared.log(.bluetooth, "Some devices nearby but 'any away' mode - proceeding with trigger")
        }

        let duration = AppSettings.shared.countdownDuration
        countdownSeconds = duration

        // Show fullscreen overlay
        overlayController.show(alarmManager: self)

        // If countdown is 0, skip directly to alarm
        if duration == 0 {
            audioManager.playAlarm()
            state = .alarming
            ActivityLogManager.shared.log(.alarm, "Immediate alarm triggered (no countdown)")
        } else {
            state = .triggered
            startCountdown()
            ActivityLogManager.shared.log(.trigger, "Countdown started (\(duration)s)")
        }
    }

    /// Immediately trigger alarm (e.g., for lid close)
    func triggerImmediate() {
        guard state == .armed || state == .triggered else { return }

        // Check Bluetooth proximity - behavior depends on auto-arm mode
        if bluetoothManager.isTrustedDeviceNearby() {
            // In "all devices away" mode: any nearby device suppresses trigger
            if AppSettings.shared.autoArmMode == .allDevicesAway {
                ActivityLogManager.shared.log(.bluetooth, "Trusted device nearby - ignoring immediate trigger")
                return
            }
            // "Any device away" mode: proceed with trigger
            ActivityLogManager.shared.log(.bluetooth, "Some devices nearby but 'any away' mode - proceeding with immediate trigger")
        }

        countdownTimer?.invalidate()
        countdownTimer = nil

        // Show overlay and start alarm
        overlayController.show(alarmManager: self)
        audioManager.playAlarm()

        state = .alarming
        ActivityLogManager.shared.log(.alarm, "ALARM ACTIVE")
    }

    // MARK: - Private Methods

    private func startCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let strongSelf = self else { return }
            Task { @MainActor in
                strongSelf.countdownSeconds -= 1
                if strongSelf.countdownSeconds <= 0 {
                    strongSelf.countdownTimer?.invalidate()
                    strongSelf.countdownTimer = nil

                    // Start alarm
                    strongSelf.audioManager.playAlarm()
                    strongSelf.state = .alarming
                    ActivityLogManager.shared.log(.alarm, "Countdown expired - ALARM ACTIVE")
                }
            }
        }
    }

    // MARK: - Auto-Arm Timer

    private func startAutoArmTimer() {
        autoArmTimer?.invalidate()
        let delay = AppSettings.shared.autoArmGracePeriod
        ActivityLogManager.shared.log(.system, "Auto-arm timer started (\(delay)s grace period)")

        autoArmTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(delay), repeats: false) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.state == .idle else { return }
                ActivityLogManager.shared.log(.armed, "Auto-arming - trusted device still away")
                self.arm()
            }
        }
    }

    private func cancelAutoArmTimer(reason: String? = nil) {
        if autoArmTimer != nil {
            ActivityLogManager.shared.log(.system, reason ?? "Auto-arm timer cancelled")
        }
        autoArmTimer?.invalidate()
        autoArmTimer = nil
    }

    /// Handle AppSettings changes - start/stop Bluetooth scanning based on auto-arm setting
    private func handleSettingsChanged() {
        guard state == .idle else { return }

        let shouldScan = AppSettings.shared.autoArmOnDeviceLeave && !bluetoothManager.trustedDevices.isEmpty

        if shouldScan && !bluetoothManager.isScanning {
            bluetoothManager.startScanning()
            ActivityLogManager.shared.log(.bluetooth, "Started scanning (auto-arm enabled)")
        } else if !shouldScan && bluetoothManager.isScanning {
            bluetoothManager.stopScanning()
            ActivityLogManager.shared.log(.bluetooth, "Stopped scanning (auto-arm disabled)")
        }
    }
}

// MARK: - InputMonitorDelegate

extension AlarmStateManager: InputMonitorDelegate {
    nonisolated func inputDetected(eventType: CGEventType) {
        Task { @MainActor in
            guard self.state == .armed else { return }

            // Log event type
            let eventName: String
            switch eventType {
            case .keyDown: eventName = "keyboard"
            case .leftMouseDown, .rightMouseDown, .otherMouseDown: eventName = "mouse click"
            case .mouseMoved: eventName = "mouse move"
            case .scrollWheel: eventName = "scroll/touchpad"
            default: eventName = "unknown"
            }
            ActivityLogManager.shared.log(.input, "Input detected: \(eventName)")

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
            ActivityLogManager.shared.log(.system, "Lid close detected - immediate alarm")
            self.triggerImmediate()
        }
    }

    nonisolated func systemDidWake() {
        Task { @MainActor in
            // Auto-disarm if trusted device is nearby on wake
            if self.bluetoothManager.isTrustedDeviceNearby() {
                self.disarm(reason: "Disarmed on wake - trusted device nearby")
            } else {
                ActivityLogManager.shared.log(.system, "System woke from sleep")
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
            ActivityLogManager.shared.log(.power, "Power cable disconnected - starting countdown")
            self.trigger()
        }
    }

    nonisolated func powerCableConnected() {
        Task { @MainActor in
            ActivityLogManager.shared.log(.power, "Power cable connected")
        }
    }
}

// MARK: - BluetoothProximityDelegate

extension AlarmStateManager: BluetoothProximityDelegate {
    nonisolated func trustedDeviceNearby(_ device: TrustedDevice) {
        Task { @MainActor in
            // Cancel pending auto-arm (always, regardless of mode)
            self.cancelAutoArmTimer(reason: "Auto-arm cancelled - '\(device.name)' detected nearby")

            // Auto-disarm logic depends on mode
            guard self.state == .armed || self.state == .triggered || self.state == .alarming else { return }

            // In "any device away" mode: only disarm when ALL devices are nearby
            // In "all devices away" mode: disarm when ANY device returns
            if AppSettings.shared.autoArmMode == .anyDeviceAway {
                // Check if ALL trusted devices are now nearby
                let allNearby = self.bluetoothManager.trustedDevices.allSatisfy { device in
                    self.bluetoothManager.isNearby(device)
                }
                if allNearby {
                    self.disarm(reason: "Disarmed - all trusted devices returned")
                }
            } else {
                // "All devices away" mode: any device returning disarms
                self.disarm(reason: "Disarmed via trusted device '\(device.name)'")
            }
        }
    }

    nonisolated func trustedDeviceAway(_ device: TrustedDevice) {
        Task { @MainActor in
            ActivityLogManager.shared.log(.bluetooth, "Trusted device '\(device.name)' left proximity")

            // For "any device away" mode - start auto-arm when any device leaves
            guard AppSettings.shared.autoArmOnDeviceLeave,
                  AppSettings.shared.autoArmMode == .anyDeviceAway,
                  self.state == .idle else { return }

            ActivityLogManager.shared.log(.bluetooth, "Any device away mode - starting grace period")
            self.startAutoArmTimer()
        }
    }

    nonisolated func allTrustedDevicesAway() {
        Task { @MainActor in
            guard AppSettings.shared.autoArmOnDeviceLeave,
                  AppSettings.shared.autoArmMode == .allDevicesAway,
                  self.state == .idle else { return }

            ActivityLogManager.shared.log(.bluetooth, "All trusted devices away - starting grace period")
            self.startAutoArmTimer()
        }
    }

    nonisolated func bluetoothStateChanged(_ state: CBManagerState) {
        Task { @MainActor in
            if state == .poweredOff {
                ActivityLogManager.shared.log(.bluetooth, "Bluetooth turned off")
            } else if state == .poweredOn {
                ActivityLogManager.shared.log(.bluetooth, "Bluetooth turned on")
            }
        }
    }
}
