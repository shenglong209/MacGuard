// AlarmRuntimeTests.swift
// MacGuard - Anti-Theft Alarm for macOS
//
// The real AlarmRuntime against a recording AlarmHardware and a manual clock.

import XCTest
@testable import MacGuard

@MainActor
private final class FakeHardware: AlarmHardware {
    enum Call: Equatable {
        case prepareAudio, lockScreen, closeConfigWindows, startInputMonitoring
        case startSystemMonitors, stopMonitors, resumeIdleScanning, stopIdleScanning
        case showOverlay, hideOverlay, playAlarm, stopAlarm
        case persistArmedMarker(ArmSession), clearArmedMarker, endOwnerChallenge
    }

    var calls: [Call] = []
    var logs: [String] = []
    var accessibilityGranted = true

    func prepareAudio() { calls.append(.prepareAudio) }
    func lockScreen() { calls.append(.lockScreen) }
    func closeConfigWindows() { calls.append(.closeConfigWindows) }
    func startInputMonitoring() -> Bool { calls.append(.startInputMonitoring); return accessibilityGranted }
    func startSystemMonitors() { calls.append(.startSystemMonitors) }
    func stopMonitors() { calls.append(.stopMonitors) }
    func resumeIdleScanning() { calls.append(.resumeIdleScanning) }
    func stopIdleScanning() { calls.append(.stopIdleScanning) }
    func showOverlay() { calls.append(.showOverlay) }
    func hideOverlay() { calls.append(.hideOverlay) }
    func playAlarm() { calls.append(.playAlarm) }
    func stopAlarm() { calls.append(.stopAlarm) }
    func persistArmedMarker(_ session: ArmSession) { calls.append(.persistArmedMarker(session)) }
    func clearArmedMarker() { calls.append(.clearArmedMarker) }
    func endOwnerChallenge() { calls.append(.endOwnerChallenge) }
    func log(_ category: ActivityLogCategory, _ message: String) { logs.append(message) }
}

/// Fires timers only when the test advances time.
@MainActor
private final class ManualScheduler: AlarmScheduler {
    final class Entry: AlarmTimer {
        var due: Date
        let interval: TimeInterval
        let repeats: Bool
        let action: @MainActor () -> Void
        var cancelled = false
        init(due: Date, interval: TimeInterval, repeats: Bool, action: @escaping @MainActor () -> Void) {
            self.due = due; self.interval = interval; self.repeats = repeats; self.action = action
        }
        func cancel() { cancelled = true }
    }

    private(set) var current = Date(timeIntervalSince1970: 0)
    private var entries: [Entry] = []

    var pending: Int { entries.filter { !$0.cancelled }.count }

    func now() -> Date { current }

    func schedule(after interval: TimeInterval, repeats: Bool, _ action: @escaping @MainActor () -> Void) -> AlarmTimer {
        let entry = Entry(due: current.addingTimeInterval(interval), interval: interval, repeats: repeats, action: action)
        entries.append(entry)
        return entry
    }

    func advance(by seconds: TimeInterval) {
        let target = current.addingTimeInterval(seconds)
        while let next = entries.filter({ !$0.cancelled && $0.due <= target }).min(by: { $0.due < $1.due }) {
            current = next.due
            if next.repeats { next.due = next.due.addingTimeInterval(next.interval) } else { next.cancelled = true }
            next.action()
        }
        current = target
    }
}

@MainActor
final class AlarmRuntimeTests: XCTestCase {
    private var hardware: FakeHardware!
    private var scheduler: ManualScheduler!
    private var env = AlarmEnvironment.fixture()
    private var runtime: AlarmRuntime!
    private var events: [AlarmEvent] = []

    override func setUp() async throws {
        hardware = FakeHardware()
        scheduler = ManualScheduler()
        events = []
        env = .fixture()
        runtime = AlarmRuntime(hardware: hardware, scheduler: scheduler,
                               environment: { [unowned self] in self.env },
                               gracePeriod: { .s15 })
        runtime.onEvent { [unowned self] in self.events.append($0) }
    }

    private func armFully() {
        runtime.send(.armRequested(auto: false))
        scheduler.advance(by: 1)
    }

    func testArmRunsDelayThenStartsMonitoringViaFeedback() {
        runtime.send(.armRequested(auto: false))
        XCTAssertEqual(runtime.state.phase, .arming)
        XCTAssertNotNil(runtime.armingDeadline)
        XCTAssertFalse(hardware.calls.contains(.startInputMonitoring), "nothing starts before the exit delay")

        scheduler.advance(by: 1)
        XCTAssertEqual(runtime.state, .armed(ArmSession(trustedDeviceHasLeft: false)))
        XCTAssertNil(runtime.armingDeadline)
        XCTAssertEqual(Array(hardware.calls.suffix(3)),
                       [.startInputMonitoring, .persistArmedMarker(ArmSession(trustedDeviceHasLeft: false)), .startSystemMonitors])
        XCTAssertEqual(events, [.armed(auto: false)])
    }

    func testMissingPermissionStandsDownThroughTheFeedbackLoop() {
        hardware.accessibilityGranted = false
        armFully()
        XCTAssertEqual(runtime.state, .idle)
        XCTAssertTrue(hardware.calls.contains(.stopMonitors))
    }

    func testCancelDuringExitDelayCancelsTheTimer() {
        env = .fixture(exitDelay: .s30)
        runtime.send(.armRequested(auto: false))
        runtime.send(.cancelArming)
        XCTAssertEqual(scheduler.pending, 0)
        scheduler.advance(by: 60)
        XCTAssertEqual(runtime.state, .idle)
        XCTAssertFalse(hardware.calls.contains(.startInputMonitoring))
    }

    /// A stale exit delay from a cancelled session must not arm a later one early.
    func testRearmWithinDelayUsesOnlyTheNewDelay() {
        env = .fixture(exitDelay: .s10)
        runtime.send(.armRequested(auto: false))
        scheduler.advance(by: 5)
        runtime.send(.cancelArming)
        runtime.send(.armRequested(auto: false))
        scheduler.advance(by: 6)  // the old delay would have fired here
        XCTAssertEqual(runtime.state.phase, .arming)
        scheduler.advance(by: 4)
        XCTAssertEqual(runtime.state.phase, .armed)
    }

    func testCountdownTimerDrivesTheAlarmAndStopsItself() {
        armFully()
        runtime.send(.intrusion(.input(.keyboard)))
        XCTAssertEqual(runtime.state.phase, .triggered)
        XCTAssertTrue(hardware.calls.contains(.showOverlay))

        scheduler.advance(by: 2)
        XCTAssertEqual(runtime.state.phase, .triggered)
        scheduler.advance(by: 1)
        XCTAssertEqual(runtime.state, .alarming(ArmSession(trustedDeviceHasLeft: false), .input(.keyboard)))
        XCTAssertEqual(hardware.calls.filter { $0 == .playAlarm }.count, 1)
        XCTAssertEqual(scheduler.pending, 0, "countdown timer is stopped once the alarm sounds")
        XCTAssertEqual(events.last, .alarmSounding(.input(.keyboard)))
    }

    func testDisarmDuringCountdownStopsEverything() {
        armFully()
        runtime.send(.intrusion(.powerDisconnected))
        runtime.send(.cancelArming)  // not allowed once armed
        XCTAssertEqual(runtime.state.phase, .triggered)

        runtime.send(.trustedDeviceAway(name: "Phone"))
        env = .fixture(any: true)
        runtime.send(.trustedDeviceNearby(name: "Phone"))
        XCTAssertEqual(runtime.state, .idle)
        XCTAssertEqual(scheduler.pending, 0)
        for call: FakeHardware.Call in [.stopMonitors, .stopAlarm, .hideOverlay, .clearArmedMarker, .endOwnerChallenge] {
            XCTAssertTrue(hardware.calls.contains(call), "\(call)")
        }
        scheduler.advance(by: 30)
        XCTAssertEqual(runtime.state, .idle, "no stale tick re-triggers")
    }

    func testAutoArmTimerArmsAfterGracePeriodAndCanBeCancelled() {
        env = .fixture(autoArm: true)
        runtime.send(.allTrustedDevicesAway)
        XCTAssertEqual(scheduler.pending, 1)
        runtime.send(.trustedDeviceNearby(name: "Phone"))
        XCTAssertEqual(scheduler.pending, 0)
        XCTAssertTrue(hardware.logs.contains("Auto-arm cancelled - 'Phone' detected nearby"))

        runtime.send(.allTrustedDevicesAway)
        scheduler.advance(by: 15)
        XCTAssertEqual(runtime.state, .arming(ArmSession(trustedDeviceHasLeft: true)))
        scheduler.advance(by: 1)
        XCTAssertEqual(events, [.armed(auto: true)])
    }

    func testTamperResumeSoundsAndRewritesTheMarker() {
        let session = ArmSession(trustedDeviceHasLeft: false)
        runtime.send(.resumeAfterTamper(session))
        XCTAssertEqual(runtime.state, .alarming(session, .tamper))
        XCTAssertTrue(hardware.calls.contains(.persistArmedMarker(session)))
        XCTAssertTrue(hardware.calls.contains(.playAlarm))
    }
}
