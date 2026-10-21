// IntruderPhotoTests.swift
// MacGuard - Anti-Theft Alarm for macOS

import XCTest
@testable import MacGuard

final class IntruderPhotoPolicyTests: XCTestCase {
    private let key = TriggerCause.input(.keyboard)

    func testCountdownTakesThePhotoAndAlarmDoesNotRetake() {
        var policy = IntruderPhotoPolicy()
        XCTAssertFalse(policy.observe(.armed(auto: false)))
        XCTAssertTrue(policy.observe(.countdownStarted(key, seconds: 3)))
        XCTAssertFalse(policy.observe(.alarmSounding(key)))
        XCTAssertFalse(policy.observe(.countdownStarted(.powerDisconnected, seconds: 3)))
    }

    func testAlarmWithoutCountdownTakesThePhoto() {
        var policy = IntruderPhotoPolicy()
        _ = policy.observe(.armed(auto: false))
        XCTAssertTrue(policy.observe(.alarmSounding(.lidClosed)))
    }

    func testEachSessionGetsOnePhoto() {
        var policy = IntruderPhotoPolicy()
        _ = policy.observe(.armed(auto: false))
        XCTAssertTrue(policy.observe(.alarmSounding(key)))
        _ = policy.observe(.disarmed(reason: "PIN"))
        _ = policy.observe(.armed(auto: true))
        XCTAssertTrue(policy.observe(.countdownStarted(key, seconds: 5)))
    }
}

final class IntruderPhotoFilesTests: XCTestCase {
    func testFilenameIsUTCSortableAndColonFree() {
        let name = IntruderPhotoFiles.filename(for: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(name, "1970-01-01T000000.000Z.jpg")
        XCTAssertFalse(name.contains(":"))

        let earlier = IntruderPhotoFiles.filename(for: Date(timeIntervalSince1970: 1_000))
        let later = IntruderPhotoFiles.filename(for: Date(timeIntervalSince1970: 2_000))
        XCTAssertLessThan(earlier, later)
    }

    func testPruneKeepsNewestAndIgnoresOtherFiles() {
        let dir = URL(fileURLWithPath: "/photos", isDirectory: true)
        let photos = (0..<5).map {
            dir.appendingPathComponent(IntruderPhotoFiles.filename(for: Date(timeIntervalSince1970: TimeInterval($0) * 60)))
        }
        let stray = dir.appendingPathComponent(".DS_Store")

        let pruned = IntruderPhotoFiles.toPrune((photos + [stray]).shuffled(), keep: 3)
        XCTAssertEqual(pruned, [photos[0], photos[1]], "oldest first, newest 3 kept")
        XCTAssertTrue(IntruderPhotoFiles.toPrune(photos, keep: 50).isEmpty)
    }
}
