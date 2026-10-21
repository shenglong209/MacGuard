// AlarmRuntime.swift
// MacGuard - Anti-Theft Alarm for macOS

import Foundation

/// The alarm's I/O. `AlarmStateManager` is the real one; tests use a recording fake.
@MainActor
protocol AlarmHardware: AnyObject {
    func prepareAudio()
    func lockScreen()
    func closeConfigWindows()
    /// false = no Accessibility permission
    func startInputMonitoring() -> Bool
    func startSystemMonitors()
    func stopMonitors()
    func resumeIdleScanning()
    func stopIdleScanning()
    func showOverlay()
    func hideOverlay()
    func playAlarm()
    func stopAlarm()
    func endOwnerChallenge()
    func log(_ category: ActivityLogCategory, _ message: String)
}

@MainActor
protocol AlarmTimer: AnyObject {
    func cancel()
}

@MainActor
protocol AlarmScheduler {
    func now() -> Date
    func schedule(after interval: TimeInterval, repeats: Bool, _ action: @escaping @MainActor () -> Void) -> AlarmTimer
}

/// Steps `AlarmMachine` and runs its effects. Feedback effects (timers,
/// `startInputMonitoring`) re-enter as inputs.
@MainActor
final class AlarmRuntime {
    private(set) var state: AlarmState = .idle {
        didSet { if state != oldValue { onStateChange(state) } }
    }
    private(set) var armingDeadline: Date? {
        didSet { onArmingDeadlineChange(armingDeadline) }
    }

    var onStateChange: (AlarmState) -> Void = { _ in }
    var onArmingDeadlineChange: (Date?) -> Void = { _ in }

    private unowned let hardware: AlarmHardware
    private let scheduler: AlarmScheduler
    private let environment: () -> AlarmEnvironment
    private let gracePeriod: () -> GracePeriod

    private var armingDelay: AlarmTimer?
    private var countdownTimer: AlarmTimer?
    private var autoArmTimer: AlarmTimer?
    private var eventSinks: [(AlarmEvent) -> Void] = []

    init(hardware: AlarmHardware,
         scheduler: AlarmScheduler,
         environment: @escaping () -> AlarmEnvironment,
         gracePeriod: @escaping () -> GracePeriod) {
        self.hardware = hardware
        self.scheduler = scheduler
        self.environment = environment
        self.gracePeriod = gracePeriod
    }

    func send(_ input: AlarmInput) {
        let (next, effects) = AlarmMachine.step(state, input, environment())
        state = next
        effects.forEach(perform)
    }

    func onEvent(_ sink: @escaping (AlarmEvent) -> Void) {
        eventSinks.append(sink)
    }

    private func perform(_ effect: AlarmEffect) {
        switch effect {
        case .prepareAudio: hardware.prepareAudio()
        case .lockScreen: hardware.lockScreen()
        case .closeConfigWindows: hardware.closeConfigWindows()
        case .scheduleArmingDelay(let delay):
            // Cancelled on reschedule or stand-down, so a stale delay can't arm a later session early.
            armingDelay?.cancel()
            armingDeadline = scheduler.now().addingTimeInterval(delay.seconds)
            armingDelay = scheduler.schedule(after: delay.seconds, repeats: false) { [weak self] in
                self?.armingDelay = nil
                self?.armingDeadline = nil
                self?.send(.armingDelayElapsed)
            }
        case .startInputMonitoring:
            send(.inputMonitoringStarted(hardware.startInputMonitoring()))
        case .startSystemMonitors: hardware.startSystemMonitors()
        case .stopMonitors:
            armingDelay?.cancel()
            armingDelay = nil
            armingDeadline = nil
            hardware.stopMonitors()
        case .showOverlay: hardware.showOverlay()
        case .hideOverlay: hardware.hideOverlay()
        case .playAlarm: hardware.playAlarm()
        case .stopAlarm: hardware.stopAlarm()
        case .startCountdownTimer:
            countdownTimer?.cancel()
            countdownTimer = scheduler.schedule(after: 1, repeats: true) { [weak self] in
                self?.send(.countdownTick)
            }
        case .stopCountdownTimer:
            countdownTimer?.cancel()
            countdownTimer = nil
        case .startAutoArmTimer:
            autoArmTimer?.cancel()
            let grace = gracePeriod()
            hardware.log(.system, "Auto-arm timer started (\(grace.rawValue)s grace period)")
            autoArmTimer = scheduler.schedule(after: grace.seconds, repeats: false) { [weak self] in
                self?.autoArmTimer = nil
                self?.send(.autoArmTimerFired)
            }
        case .cancelAutoArmTimer(let reason):
            if let timer = autoArmTimer {
                hardware.log(.system, reason ?? "Auto-arm timer cancelled")
                timer.cancel()
                autoArmTimer = nil
            }
        case .resumeIdleScanning: hardware.resumeIdleScanning()
        case .stopIdleScanning: hardware.stopIdleScanning()
        case .log(let category, let message): hardware.log(category, message)
        case .emit(let event): eventSinks.forEach { $0(event) }
        case .endOwnerChallenge: hardware.endOwnerChallenge()
        }
    }
}

/// `.common` mode, so timers keep firing while a menu is open.
struct RunLoopScheduler: AlarmScheduler {
    private final class RunLoopTimer: AlarmTimer {
        let timer: Timer
        init(_ timer: Timer) { self.timer = timer }
        func cancel() { timer.invalidate() }
    }

    func now() -> Date { Date() }

    func schedule(after interval: TimeInterval, repeats: Bool, _ action: @escaping @MainActor () -> Void) -> AlarmTimer {
        let timer = Timer(timeInterval: interval, repeats: repeats) { _ in
            MainActor.assumeIsolated { action() }
        }
        RunLoop.main.add(timer, forMode: .common)
        return RunLoopTimer(timer)
    }
}
