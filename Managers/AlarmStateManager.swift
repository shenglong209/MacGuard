// AlarmStateManager.swift
// MacGuard - Anti-Theft Alarm for macOS
// Created: 2025-12-18

import SwiftUI
import Combine

/// Imperative shell around `AlarmMachine`: parses callbacks into inputs, performs effects.
@MainActor
class AlarmStateManager: ObservableObject {
    // MARK: - Published Properties

    @Published private(set) var state: AlarmState = .idle
    @Published var hasAccessibilityPermission = false
    /// Display only; the machine decides via `.armingDelayElapsed`.
    @Published private(set) var armingDeadline: Date?

    // MARK: - Public Managers (for UI access)

    let bluetoothManager = BluetoothProximityManager()
    let authManager = AuthManager()
    let audioManager = AlarmAudioManager()

    // MARK: - Private Properties

    private var permissionCheckTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let inputMonitor = InputMonitor()
    private let sleepMonitor = SleepMonitor()
    private let powerMonitor = PowerMonitor()
    private let usbMonitor = USBMonitor()
    private let networkMonitor = NetworkMonitor()
    private lazy var overlayController = CountdownWindowController(alarmManager: self)

    private lazy var runtime: AlarmRuntime = {
        let runtime = AlarmRuntime(
            hardware: self,
            scheduler: RunLoopScheduler(),
            environment: { [unowned self] in self.environment },
            gracePeriod: { AppSettings.shared.autoArmGracePeriod }
        )
        runtime.onStateChange = { [unowned self] in self.state = $0 }
        runtime.onArmingDeadlineChange = { [unowned self] in self.armingDeadline = $0 }
        return runtime
    }()

    // MARK: - Initialization

    init() {
        // Every monitor delivers on the main run loop, already parsed
        let forward: (AlarmInput) -> Void = { [weak self] input in
            MainActor.assumeIsolated { self?.send(input) }
        }
        inputMonitor.onInput = forward
        sleepMonitor.onInput = forward
        powerMonitor.onInput = forward
        usbMonitor.onInput = forward
        networkMonitor.onInput = forward
        bluetoothManager.onInput = forward
        checkPermissions()
        startPermissionPolling()

        // Always observed (an idle-time signal); the machine decides whether it arms.
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.send(.screenLocked) }
        }

        // Forward nested managers' changes so views observing this one redraw
        Publishers.Merge(bluetoothManager.objectWillChange, authManager.objectWillChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Delivered after the change (objectWillChange fires before it)
        AppSettings.shared.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.send(.settingsChanged)
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

    // MARK: - Machine

    private var environment: AlarmEnvironment {
        let settings = AppSettings.shared
        return AlarmEnvironment(
            countdown: settings.countdownDuration.countdown,
            autoLockOnArm: settings.autoLockOnArm,
            autoArmEnabled: settings.autoArmOnDeviceLeave,
            autoArmMode: settings.autoArmMode,
            hasTrustedDevices: !bluetoothManager.trustedDevices.isEmpty,
            anyTrustedDeviceNearby: bluetoothManager.isTrustedDeviceNearby(),
            allTrustedDevicesNearby: bluetoothManager.areAllDevicesNearby,
            bluetoothStable: bluetoothManager.isBluetoothStable,
            usbTriggerEnabled: settings.usbTriggerEnabled,
            networkTriggerEnabled: settings.networkTriggerEnabled,
            autoArmOnScreenLock: settings.autoArmOnScreenLock,
            exitDelay: settings.exitDelay
        )
    }

    private func send(_ input: AlarmInput) {
        runtime.send(input)
    }

    func onEvent(_ sink: @escaping (AlarmEvent) -> Void) {
        runtime.onEvent(sink)
    }

    // MARK: - Actions (UI)

    /// Arm the alarm system, optionally lock screen, and start monitoring
    func arm() {
        send(.armRequested(auto: false))
    }

    /// No authentication: nothing is guarded yet.
    func cancelArming() {
        send(.cancelArming)
    }

    func disarm(_ proof: OwnerAuthentication) {
        send(.authenticated(proof))
    }

    func requestDisarm(completion: @escaping (Bool) -> Void = { _ in }) {
        authManager.authenticate { [weak self] proof in
            guard let self, let proof else { return completion(false) }
            self.disarm(proof)
            completion(true)
        }
    }

    func attemptPINDisarm(_ pin: String) -> PINVerification {
        let result = authManager.verifyPIN(pin)
        if case .accepted(let proof) = result {
            disarm(proof)
        }
        return result
    }

    /// Idle only, so the record of an intrusion survives.
    func clearActivityLog() {
        guard state == .idle else { return }
        ActivityLogManager.shared.clear()
    }

    /// Lock the Mac screen
    func lockScreen() {
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
}

// MARK: - AlarmHardware

extension AlarmStateManager: AlarmHardware {
    func prepareAudio() { audioManager.prepare() }

    func closeConfigWindows() {
        // Config windows opened while idle must not stay editable once armed
        PINSetupWindowController.shared.close()
        TrustedDevicesConfigWindowController.shared.close()
        DeviceScannerWindowController.shared.close()
    }

    func startInputMonitoring() -> Bool {
        let started = inputMonitor.startMonitoring()
        hasAccessibilityPermission = started
        return started
    }

    func startSystemMonitors() {
        sleepMonitor.startMonitoring()
        powerMonitor.startMonitoring()
        usbMonitor.startMonitoring()
        networkMonitor.startMonitoring()
        bluetoothManager.startScanning()
        bluetoothManager.setArmedState(true)
    }

    func stopMonitors() {
        inputMonitor.stopMonitoring()
        usbMonitor.stopMonitoring()
        networkMonitor.stopMonitoring()
        sleepMonitor.stopMonitoring()
        powerMonitor.stopMonitoring()
        bluetoothManager.setArmedState(false)
        bluetoothManager.stopScanning()
    }

    func resumeIdleScanning() { bluetoothManager.startScanning() }
    func stopIdleScanning() { bluetoothManager.stopScanning() }
    func showOverlay() { overlayController.show() }
    func hideOverlay() { overlayController.hide() }
    func playAlarm() { audioManager.playAlarm() }

    func stopAlarm() {
        audioManager.stopAlarm()
        audioManager.unprepare()
    }

    func endOwnerChallenge() {
        authManager.resetPINAttempts()
        authManager.cancelPendingAuthentication()
    }
    func log(_ category: ActivityLogCategory, _ message: String) { ActivityLogManager.shared.log(category, message) }
}
