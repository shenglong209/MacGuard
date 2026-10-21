// PINThrottleTests.swift
// MacGuard - Anti-Theft Alarm for macOS

import XCTest
@testable import MacGuard

final class PINThrottleTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testFreeAttemptsThenDoublingLockoutThatExpires() {
        var throttle = PINThrottle()
        for _ in 0..<PINThrottle.freeAttempts { XCTAssertNil(throttle.recordFailure(at: t0)) }
        XCTAssertNil(throttle.lockout(at: t0))

        XCTAssertEqual(throttle.recordFailure(at: t0), t0.addingTimeInterval(30))
        XCTAssertEqual(throttle.lockout(at: t0.addingTimeInterval(29)), t0.addingTimeInterval(30))
        XCTAssertNil(throttle.lockout(at: t0.addingTimeInterval(30)), "lockout ends exactly at its deadline")

        let t1 = t0.addingTimeInterval(30)
        XCTAssertEqual(throttle.recordFailure(at: t1), t1.addingTimeInterval(60))
    }

    func testLockoutIsCapped() {
        var throttle = PINThrottle()
        var until: Date?
        for _ in 0..<50 { until = throttle.recordFailure(at: t0) }
        XCTAssertEqual(until, t0.addingTimeInterval(30 * 1024))
    }

    func testSuccessResets() {
        var throttle = PINThrottle()
        for _ in 0..<5 { _ = throttle.recordFailure(at: t0) }
        throttle.recordSuccess()
        XCTAssertEqual(throttle, PINThrottle())
    }

    func testConstantTimeEquals() {
        XCTAssertTrue(AuthManager.constantTimeEquals(Data("1234".utf8), Data("1234".utf8)))
        XCTAssertFalse(AuthManager.constantTimeEquals(Data("1234".utf8), Data("1235".utf8)))
        XCTAssertFalse(AuthManager.constantTimeEquals(Data("1234".utf8), Data("12345".utf8)))
    }
}

final class PINWeaknessTests: XCTestCase {
    private func weakness(_ raw: String) -> PINWeakness? { PIN(raw)?.weakness }

    func testClassifies() {
        let cases: [(String, PINWeakness?)] = [
            ("12345", .luggage), ("1234", .luggage), ("0000", .repeated), ("99999999", .repeated),
            ("2345", .sequence), ("9876", .sequence), ("2580", .common),
            ("4071", nil), ("8352", nil), ("13579", nil), ("90210", nil), ("246813", nil),
        ]
        for (raw, expected) in cases {
            XCTAssertEqual(weakness(raw), expected, raw)
        }
    }
}

final class PINThrottlePersistenceTests: XCTestCase {
    func testLockoutSurvivesARoundTrip() throws {
        var throttle = PINThrottle()
        let now = Date(timeIntervalSince1970: 1_000)
        for _ in 0..<4 { _ = throttle.recordFailure(at: now) }
        let restored = try JSONDecoder().decode(PINThrottle.self, from: JSONEncoder().encode(throttle))
        XCTAssertEqual(restored, throttle)
        XCTAssertNotNil(restored.lockout(at: now.addingTimeInterval(10)), "a relaunch must not end the lockout")
    }
}
