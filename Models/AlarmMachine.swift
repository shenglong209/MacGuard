// AlarmMachine.swift
// MacGuard - Anti-Theft Alarm for macOS

import Foundation

/// Why the alarm was set off, parsed at the monitor boundary.
enum TriggerCause: Equatable {
    case input(IntrusionInput)
    case powerDisconnected
    case lidClosed

    var label: String {
        switch self {
        case .input(let input): return input.label
        case .powerDisconnected: return "power cable disconnected"
        case .lidClosed: return "lid closed"
        }
    }
}

/// Security-relevant facts for observers, so none has to interpret raw state.
enum AlarmEvent: Equatable {
    case armed(auto: Bool)
    case disarmed(reason: String)
    case countdownStarted(TriggerCause, seconds: Int)
    case alarmSounding(TriggerCause)
}

enum AlarmInput {
    case armRequested(auto: Bool)
    case armingDelayElapsed
    case inputMonitoringStarted(Bool)
    case cancelArming
    case authenticated(OwnerAuthentication)
    /// Starts the countdown, or sounds at once when there is none.
    case intrusion(TriggerCause)
    /// Sounds immediately, even mid-countdown.
    case severeIntrusion(TriggerCause)
    case countdownTick
    case trustedDeviceNearby(name: String)
    case trustedDeviceAway(name: String)
    case allTrustedDevicesAway
    case systemWoke
    case autoArmTimerFired
    case settingsChanged
}

/// Snapshot of parsed settings and proximity *evidence* the machine decides on.
struct AlarmEnvironment {
    var countdown: Countdown?
    var autoLockOnArm: Bool
    var autoArmEnabled: Bool
    var autoArmMode: AutoArmMode
    var hasTrustedDevices: Bool
    /// Positive evidence only: false while proximity is merely assumed.
    var anyTrustedDeviceNearby: Bool
    var allTrustedDevicesNearby: Bool
    var bluetoothStable: Bool
    var exitDelay: ExitDelay
}

/// Side effects the shell performs, in order.
enum AlarmEffect: Equatable {
    case prepareAudio
    case lockScreen
    case closeConfigWindows
    case scheduleArmingDelay(ExitDelay)
    case startInputMonitoring
    case startSystemMonitors
    case stopMonitors
    case showOverlay
    case hideOverlay
    case playAlarm
    case stopAlarm
    case startCountdownTimer
    case stopCountdownTimer
    case startAutoArmTimer
    case cancelAutoArmTimer(reason: String?)
    case resumeIdleScanning
    case stopIdleScanning
    case log(ActivityLogCategory, String)
    case emit(AlarmEvent)
    /// Disarmed: drop wrong-PIN history and any open Touch ID prompt.
    case endOwnerChallenge
}

/// The alarm's decisions as a pure function: no timers, singletons or I/O.
enum AlarmMachine {
    typealias Transition = (state: AlarmState, effects: [AlarmEffect])

    static func step(_ state: AlarmState, _ input: AlarmInput, _ env: AlarmEnvironment) -> Transition {
        switch (state, input) {

        // MARK: Arming
        case (.idle, .armRequested(let auto)):
            var effects: [AlarmEffect] = [.closeConfigWindows, .prepareAudio]
            if env.autoLockOnArm { effects.append(.lockScreen) }
            effects.append(.scheduleArmingDelay(env.exitDelay))
            return (.arming(ArmSession(trustedDeviceHasLeft: auto)), effects)

        case (.arming, .armingDelayElapsed):
            return (state, [.startInputMonitoring])

        case (.arming(let session), .inputMonitoringStarted(true)):
            return (.armed(session), [
                .startSystemMonitors,
                .log(.armed, "System armed - monitoring active"),
                .emit(.armed(auto: session.trustedDeviceHasLeft)),
            ])

        case (.arming, .inputMonitoringStarted(false)):
            return standDown("Failed to arm - accessibility permission denied", env)

        case (.arming, .cancelArming):
            return standDown("Arming cancelled", env)

        // MARK: Disarming
        case (_, .authenticated(let proof)) where state != .idle:
            return standDown("Disarmed via \(proof.method.rawValue)", env)

        // MARK: Triggering
        case (.armed(let session), .intrusion(let cause)):
            if let suppressed = suppression(env) { return (state, [suppressed]) }
            guard let countdown = env.countdown else {
                return soundAlarm(session, cause, "Immediate alarm triggered (no countdown)", overlay: true)
            }
            return (.triggered(session, countdown, cause), [
                .showOverlay,
                .startCountdownTimer,
                .log(.trigger, "Countdown started (\(countdown.total)s) - \(cause.label)"),
                .emit(.countdownStarted(cause, seconds: countdown.total)),
            ])

        case (.armed(let session), .severeIntrusion(let cause)),
             (.triggered(let session, _, _), .severeIntrusion(let cause)):
            if let suppressed = suppression(env) { return (state, [suppressed]) }
            return soundAlarm(session, cause, "ALARM ACTIVE - \(cause.label)", overlay: true)

        case (.triggered(let session, let countdown, let cause), .countdownTick):
            guard let next = countdown.ticked() else {
                return soundAlarm(session, cause, "Countdown expired - ALARM ACTIVE", overlay: false)
            }
            return (.triggered(session, next, cause), [])

        // MARK: Proximity
        case (_, .trustedDeviceNearby(let name)):
            let cancel = AlarmEffect.cancelAutoArmTimer(reason: "Auto-arm cancelled - '\(name)' detected nearby")
            guard let session = state.session else { return (state, [cancel]) }
            if proximityMayDisarm(state, env) {
                let (next, effects) = standDown("Disarmed via trusted device '\(name)'", env)
                return (next, [cancel] + effects)
            }
            guard !session.trustedDeviceHasLeft else { return (state, [cancel]) }
            return (state, [cancel, .log(.bluetooth, "Device '\(name)' nearby but manual arm - not auto-disarming")])

        case (_, .trustedDeviceAway(let name)):
            var effects: [AlarmEffect] = [.log(.bluetooth, "Trusted device '\(name)' left proximity")]
            var next = state
            if state.session?.trustedDeviceHasLeft == false {
                next = state.updatingSession { $0.trustedDeviceHasLeft = true }
                effects.append(.log(.bluetooth, "Device left while armed - enabling auto-disarm on return"))
            }
            if next == .idle, env.autoArmEnabled, env.autoArmMode == .anyDeviceAway {
                effects += autoArmGracePeriod("Any device away mode - starting grace period", env)
            }
            return (next, effects)

        case (.idle, .allTrustedDevicesAway):
            guard env.autoArmEnabled, env.autoArmMode == .allDevicesAway else { return (state, []) }
            return (state, autoArmGracePeriod("All trusted devices away - starting grace period", env))

        case (_, .systemWoke):
            if proximityMayDisarm(state, env) {
                return standDown("Disarmed on wake - trusted device nearby", env)
            }
            return (state, [.log(.system, "System woke from sleep")])

        case (.idle, .autoArmTimerFired):
            let (next, effects) = step(.idle, .armRequested(auto: true), env)
            return (next, [.log(.armed, "Auto-arming - trusted device still away")] + effects)

        case (.idle, .settingsChanged):
            return (state, [wantsIdleScanning(env) ? .resumeIdleScanning : .stopIdleScanning])

        // Anything else is a no-op here (e.g. a stale tick after disarm).
        default:
            return (state, [])
        }
    }

    // MARK: - Rules

    /// A nearby trusted device swallows intrusions, except in "any device away" mode.
    private static func suppression(_ env: AlarmEnvironment) -> AlarmEffect? {
        guard env.anyTrustedDeviceNearby, env.autoArmMode == .allDevicesAway else { return nil }
        return .log(.bluetooth, "Trusted device nearby - ignoring trigger")
    }

    /// Every proximity disarm (return, wake): only once a device has left this session.
    static func proximityMayDisarm(_ state: AlarmState, _ env: AlarmEnvironment) -> Bool {
        guard let session = state.session, state.phase != .arming,
              session.trustedDeviceHasLeft else { return false }
        switch env.autoArmMode {
        case .allDevicesAway: return env.anyTrustedDeviceNearby
        case .anyDeviceAway: return env.allTrustedDevicesNearby
        }
    }

    private static func autoArmGracePeriod(_ message: String, _ env: AlarmEnvironment) -> [AlarmEffect] {
        guard env.bluetoothStable else {
            return [.log(.bluetooth, "Auto-arm blocked - BT unstable or off")]
        }
        return [.log(.bluetooth, message), .startAutoArmTimer]
    }

    private static func soundAlarm(_ session: ArmSession, _ cause: TriggerCause, _ message: String, overlay: Bool) -> Transition {
        let effects: [AlarmEffect] = (overlay ? [.showOverlay] : []) + [
            .stopCountdownTimer,
            .playAlarm,
            .log(.alarm, message),
            .emit(.alarmSounding(cause)),
        ]
        return (.alarming(session, cause), effects)
    }

    private static func standDown(_ reason: String, _ env: AlarmEnvironment) -> Transition {
        var effects: [AlarmEffect] = [
            .stopCountdownTimer,
            .cancelAutoArmTimer(reason: nil),
            .stopMonitors,
            .stopAlarm,
            .hideOverlay,
            // PIN attempts only accrue while triggered or alarming, which end
            // only with owner proof or a trusted device's return.
            .endOwnerChallenge,
            .log(.disarmed, reason),
            .emit(.disarmed(reason: reason)),
        ]
        if wantsIdleScanning(env) { effects.append(.resumeIdleScanning) }
        return (.idle, effects)
    }

    /// Idle scanning only when auto-arm needs it (keeps idle CPU low).
    private static func wantsIdleScanning(_ env: AlarmEnvironment) -> Bool {
        env.autoArmEnabled && env.hasTrustedDevices
    }
}
