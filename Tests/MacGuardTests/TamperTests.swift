// TamperTests.swift
// MacGuard - Anti-Theft Alarm for macOS

import XCTest
@testable import MacGuard

final class TamperMachineTests: XCTestCase {
    private let manual = ArmSession(trustedDeviceHasLeft: false)
    private let left = ArmSession(trustedDeviceHasLeft: true)

    private let env = AlarmEnvironment.fixture()

    func testArmingPersistsTheMarker() {
        let effects = AlarmMachine.step(.arming(left), .inputMonitoringStarted(true), env).effects
        XCTAssertEqual(effects.first, .persistArmedMarker(left))
    }

    func testEveryStandDownClearsTheMarker() {
        let standDowns: [(AlarmState, AlarmInput)] = [
            (.arming(manual), .cancelArming),
            (.arming(manual), .inputMonitoringStarted(false)),
            (.armed(left), .trustedDeviceNearby(name: "Phone")),
            (.alarming(left, .tamper), .systemWoke),
        ]
        let nearby = AlarmEnvironment.fixture(countdown: 0, any: true, all: true)
        for (state, input) in standDowns {
            let (next, effects) = AlarmMachine.step(state, input, nearby)
            XCTAssertEqual(next, .idle, "\(state) + \(input)")
            for required: AlarmEffect in [.stopCountdownTimer, .stopMonitors, .stopAlarm, .hideOverlay,
                                          .clearArmedMarker, .endOwnerChallenge] {
                XCTAssertTrue(effects.contains(required), "\(state) + \(input): \(required)")
            }
        }
    }

    /// Sounds at once with the stored session: a killed manual arm gains no proximity-disarm rights.
    func testResumeAfterTamperSoundsWithTheStoredSession() {
        for session in [left, manual] {
            let (state, effects) = AlarmMachine.step(.idle, .resumeAfterTamper(session), env)
            XCTAssertEqual(state, .alarming(session, .tamper))
            for required: AlarmEffect in [.persistArmedMarker(session), .startSystemMonitors, .showOverlay,
                                          .playAlarm, .emit(.alarmSounding(.tamper))] {
                XCTAssertTrue(effects.contains(required), "\(session): \(required)")
            }
        }
    }

    func testResumeIgnoredWhenAlreadyActive() {
        XCTAssertEqual(AlarmMachine.step(.armed(manual), .resumeAfterTamper(left), env).state, .armed(manual))
    }
}

final class LaunchDecisionTests: XCTestCase {
    private func markerData(left: Bool, pid: Int32) throws -> Data {
        try TamperGuard.encoder.encode(ArmedMarker(ArmSession(trustedDeviceHasLeft: left), armedAt: Date(), pid: pid))
    }

    func testDecision() throws {
        let cases: [(String, Data?, Bool, LaunchDecision)] = [
            ("no marker", nil, false, .normal),
            ("dead owner", try markerData(left: true, pid: 4242), false,
             .resumeAfterTamper(ArmSession(trustedDeviceHasLeft: true))),
            ("live owner", try markerData(left: false, pid: 4242), true, .normal),
            ("corrupt marker fails closed", Data("garbage".utf8), true,
             .resumeAfterTamper(ArmSession(trustedDeviceHasLeft: false))),
        ]
        for (name, data, alive, expected) in cases {
            XCTAssertEqual(LaunchDecision.decide(markerData: data) { _ in alive }, expected, name)
        }
    }

    func testOwnProcessIsRecognised() {
        XCTAssertTrue(TamperGuard.isMacGuardProcess(getpid()))
        XCTAssertFalse(TamperGuard.isMacGuardProcess(1), "launchd is not MacGuard")
        XCTAssertFalse(TamperGuard.isMacGuardProcess(-1))
    }
}
