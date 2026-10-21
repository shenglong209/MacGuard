// AlarmMachineTests.swift
// MacGuard - Anti-Theft Alarm for macOS

import XCTest
@testable import MacGuard

final class AlarmMachineTests: XCTestCase {
    private let manual = ArmSession(trustedDeviceHasLeft: false)
    private let left = ArmSession(trustedDeviceHasLeft: true)
    private let key = TriggerCause.input(.keyboard)

    private func step(_ s: AlarmState, _ i: AlarmInput, _ e: AlarmEnvironment = .fixture()) -> AlarmMachine.Transition {
        AlarmMachine.step(s, i, e)
    }

    // MARK: Arming

    func testArmEntersArmingSynchronously() {
        let (state, effects) = step(.idle, .armRequested(auto: false))
        XCTAssertEqual(state, .arming(manual))
        XCTAssertEqual(effects, [.closeConfigWindows, .prepareAudio, .scheduleArmingDelay(.s1)])
        XCTAssertTrue(step(.idle, .armRequested(auto: false), .fixture(exitDelay: .s30)).effects
            .contains(.scheduleArmingDelay(.s30)))
    }

    func testArmLocksScreenOnlyWhenConfigured() {
        XCTAssertTrue(step(.idle, .armRequested(auto: false), .fixture(autoLock: true)).effects.contains(.lockScreen))
    }

    func testSecondArmRequestIsIgnored() {
        XCTAssertTrue(step(.arming(manual), .armRequested(auto: false)).effects.isEmpty)
        XCTAssertTrue(step(.armed(manual), .armRequested(auto: false)).effects.isEmpty)
    }

    func testArmingCompletesWhenInputMonitoringStarts() {
        XCTAssertEqual(step(.arming(manual), .armingDelayElapsed).effects, [.startInputMonitoring])
        let (state, effects) = step(.arming(manual), .inputMonitoringStarted(true))
        XCTAssertEqual(state, .armed(manual))
        XCTAssertTrue(effects.contains(.emit(.armed(auto: false))))
    }

    func testDelayAfterCancelDoesNotArm() {
        let (cancelled, _) = step(.arming(manual), .cancelArming)
        XCTAssertEqual(cancelled, .idle)
        XCTAssertEqual(step(cancelled, .armingDelayElapsed).state, .idle)
        XCTAssertEqual(step(cancelled, .inputMonitoringStarted(true)).state, .idle)
    }

    func testIntrusionsIgnoredUnlessArmed() {
        let inputs: [AlarmInput] = [.intrusion(key), .severeIntrusion(.lidClosed), .intrusion(.powerDisconnected)]
        for state: AlarmState in [.idle, .arming(manual)] {
            for input in inputs {
                XCTAssertEqual(step(state, input, .fixture()).state, state, "\(state) + \(input)")
            }
        }
    }

    func testCancelArmingCannotDisarmAnArmedSystem() {
        XCTAssertEqual(step(.armed(manual), .cancelArming).state, .armed(manual))
    }

    // MARK: Triggering

    func testIntrusionStartsCountdown() throws {
        let (state, effects) = step(.armed(manual), .intrusion(key))
        XCTAssertEqual(state, .triggered(manual, try XCTUnwrap(Countdown(seconds: 3)), key))
        XCTAssertTrue(effects.contains(.showOverlay))
        XCTAssertTrue(effects.contains(.startCountdownTimer))
        XCTAssertTrue(effects.contains(.emit(.countdownStarted(key, seconds: 3))))
    }

    func testNoCountdownSoundsImmediately() {
        let (state, effects) = step(.armed(manual), .intrusion(.powerDisconnected), .fixture(countdown: 0))
        XCTAssertEqual(state, .alarming(manual, .powerDisconnected))
        XCTAssertTrue(effects.contains(.playAlarm))
    }

    func testCountdownTicksThenSoundsWithOriginalCause() throws {
        var state = AlarmState.triggered(manual, try XCTUnwrap(Countdown(seconds: 2)), key)
        state = step(state, .countdownTick).state
        guard case .triggered(_, let countdown, _) = state else { return XCTFail("still counting down") }
        XCTAssertEqual(countdown.remaining, 1)

        let (final, effects) = step(state, .countdownTick)
        XCTAssertEqual(final, .alarming(manual, key))
        XCTAssertTrue(effects.contains(.emit(.alarmSounding(key))))
        XCTAssertFalse(effects.contains(.showOverlay), "overlay is already up")
    }

    func testStaleTickAfterDisarmIsNoOp() {
        XCTAssertEqual(step(.idle, .countdownTick).state, .idle)
        XCTAssertTrue(step(.idle, .countdownTick).effects.isEmpty)
    }

    func testSevereIntrusionEscalatesMidCountdown() throws {
        let triggered = AlarmState.triggered(manual, try XCTUnwrap(Countdown(seconds: 10)), key)
        XCTAssertEqual(step(triggered, .severeIntrusion(.lidClosed)).state, .alarming(manual, .lidClosed))
        XCTAssertEqual(step(.armed(manual), .severeIntrusion(.lidClosed)).state, .alarming(manual, .lidClosed))
    }

    func testNearbyDeviceSuppressesOnlyInAllDevicesAwayMode() {
        XCTAssertEqual(step(.armed(manual), .intrusion(key), .fixture(mode: .allDevicesAway, any: true)).state, .armed(manual))
        XCTAssertEqual(step(.armed(manual), .severeIntrusion(.lidClosed), .fixture(mode: .allDevicesAway, any: true)).state, .armed(manual))
        XCTAssertNotEqual(step(.armed(manual), .intrusion(key), .fixture(mode: .anyDeviceAway, any: true)).state, .armed(manual))
    }

    // MARK: Proximity disarm

    func testManualArmIsNotDisarmedByPresentDevice() {
        let (state, effects) = step(.armed(manual), .trustedDeviceNearby(name: "Phone"), .fixture(any: true))
        XCTAssertEqual(state, .armed(manual))
        XCTAssertTrue(effects.contains(.log(.bluetooth, "Device 'Phone' nearby but manual arm - not auto-disarming")))
    }

    func testDeviceThatLeftThenReturnedDisarms() {
        let away = step(.armed(manual), .trustedDeviceAway(name: "Phone")).state
        XCTAssertEqual(away, .armed(left))
        XCTAssertEqual(step(away, .trustedDeviceNearby(name: "Phone"), .fixture(any: true)).state, .idle)
    }

    func testReturnDisarmsDuringAlarmToo() {
        XCTAssertEqual(step(.alarming(left, key), .trustedDeviceNearby(name: "Phone"), .fixture(any: true)).state, .idle)
    }

    func testAnyDeviceAwayModeNeedsAllDevicesBack() {
        let partial = AlarmEnvironment.fixture(mode: .anyDeviceAway, any: true, all: false)
        XCTAssertEqual(step(.armed(left), .trustedDeviceNearby(name: "Phone"), partial).state, .armed(left))
        XCTAssertEqual(step(.armed(left), .trustedDeviceNearby(name: "Watch"), .fixture(mode: .anyDeviceAway, any: true, all: true)).state, .idle)
    }

    /// Including the manual-arm rule and "any device away" mode.
    func testWakeFollowsTheSameRule() {
        XCTAssertEqual(step(.armed(manual), .systemWoke, .fixture(any: true)).state, .armed(manual))
        XCTAssertEqual(step(.armed(left), .systemWoke, .fixture(mode: .anyDeviceAway, any: true, all: false)).state, .armed(left))
        XCTAssertEqual(step(.armed(left), .systemWoke, .fixture(any: true)).state, .idle)
    }

    func testNoProximityDisarmWhileArming() {
        XCTAssertEqual(step(.arming(left), .trustedDeviceNearby(name: "Phone"), .fixture(any: true)).state, .arming(left))
    }

    func testNearbyAlwaysCancelsAutoArmTimer() {
        XCTAssertEqual(step(.idle, .trustedDeviceNearby(name: "Phone")).effects,
                       [.cancelAutoArmTimer(reason: "Auto-arm cancelled - 'Phone' detected nearby")])
    }

    // MARK: Auto-arm

    func testAllAwayStartsGracePeriodOnlyWhenEnabledAndStable() {
        XCTAssertTrue(step(.idle, .allTrustedDevicesAway, .fixture(autoArm: true)).effects.contains(.startAutoArmTimer))
        XCTAssertFalse(step(.idle, .allTrustedDevicesAway, .fixture(autoArm: false)).effects.contains(.startAutoArmTimer))
        XCTAssertFalse(step(.idle, .allTrustedDevicesAway, .fixture(autoArm: true, stable: false)).effects.contains(.startAutoArmTimer))
        XCTAssertFalse(step(.idle, .allTrustedDevicesAway, .fixture(autoArm: true, mode: .anyDeviceAway)).effects.contains(.startAutoArmTimer))
    }

    func testAnyAwayModeStartsGracePeriodOnSingleDeparture() {
        let effects = step(.idle, .trustedDeviceAway(name: "Phone"), .fixture(autoArm: true, mode: .anyDeviceAway)).effects
        XCTAssertTrue(effects.contains(.startAutoArmTimer))
    }

    func testAutoArmTimerArmsAsDeviceLeft() {
        XCTAssertEqual(step(.idle, .autoArmTimerFired).state, .arming(left))
        XCTAssertEqual(step(.armed(manual), .autoArmTimerFired).state, .armed(manual))
    }

    // MARK: Stand down

    func testStandDownResumesIdleScanningOnlyWhenAutoArmConfigured() {
        XCTAssertTrue(step(.arming(manual), .cancelArming, .fixture(autoArm: true, devices: true)).effects.contains(.resumeIdleScanning))
        XCTAssertFalse(step(.arming(manual), .cancelArming, .fixture(autoArm: true, devices: false)).effects.contains(.resumeIdleScanning))
        XCTAssertFalse(step(.arming(manual), .cancelArming, .fixture(autoArm: false)).effects.contains(.resumeIdleScanning))
    }

    func testSettingsChangeAppliesTheIdleScanningRule() {
        XCTAssertEqual(step(.idle, .settingsChanged, .fixture(autoArm: true, devices: true)).effects, [.resumeIdleScanning])
        XCTAssertEqual(step(.idle, .settingsChanged, .fixture(autoArm: true, devices: false)).effects, [.stopIdleScanning])
        XCTAssertEqual(step(.idle, .settingsChanged, .fixture(autoArm: false)).effects, [.stopIdleScanning])
    }

    func testSettingsChangeLeavesActiveScanningAlone() {
        for state: AlarmState in [.arming(manual), .armed(manual)] {
            XCTAssertEqual(step(state, .settingsChanged, .fixture(autoArm: false)).effects, [], "\(state)")
        }
    }
}

final class StandDownTests: XCTestCase {
    func testEveryStandDownStopsEverythingAndEndsTheOwnerChallenge() {
        let manual = ArmSession(trustedDeviceHasLeft: false)
        let left = ArmSession(trustedDeviceHasLeft: true)
        let standDowns: [(AlarmState, AlarmInput)] = [
            (.arming(manual), .cancelArming),
            (.arming(manual), .inputMonitoringStarted(false)),
            (.armed(left), .trustedDeviceNearby(name: "Phone")),
            (.alarming(left, .input(.keyboard)), .systemWoke),
        ]
        let nearby = AlarmEnvironment.fixture(countdown: 0, any: true, all: true)
        for (state, input) in standDowns {
            let (next, effects) = AlarmMachine.step(state, input, nearby)
            XCTAssertEqual(next, .idle, "\(state) + \(input)")
            for required: AlarmEffect in [.stopCountdownTimer, .stopMonitors, .stopAlarm, .hideOverlay, .endOwnerChallenge] {
                XCTAssertTrue(effects.contains(required), "\(state) + \(input): \(required)")
            }
        }
    }
}
