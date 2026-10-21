// MotionSensingTests.swift
// MacGuard - Anti-Theft Alarm for macOS

import XCTest
@testable import MacGuard

final class MotionSensingTests: XCTestCase {
    private let rest = Acceleration(x: 0, y: -0.22, z: -0.97)

    private func detector(_ sensitivity: MotionSensitivity = .medium) -> MotionDetector {
        var detector = MotionDetector(sensitivity: sensitivity)
        for _ in 0..<MotionDetector.warmUpSamples { XCTAssertNil(detector.add(rest)) }
        return detector
    }

    func testParsesReportAxes() {
        var bytes = [UInt8](repeating: 0, count: 22)
        for (offset, raw) in [(6, Int32(65536)), (10, Int32(-32768)), (14, Int32(0))] {
            withUnsafeBytes(of: raw.littleEndian) { bytes.replaceSubrange(offset..<offset + 4, with: $0) }
        }
        let a = bytes.withUnsafeBytes { Acceleration(report: $0) }
        XCTAssertEqual(a, Acceleration(x: 1, y: -0.5, z: 0))
        XCTAssertNil([UInt8](repeating: 0, count: 17).withUnsafeBytes { Acceleration(report: $0) })
    }

    func testRestingNoiseDoesNotTrigger() {
        var d = detector(.high)
        for i in 0..<1000 {
            let jitter = (i % 2 == 0 ? 1.0 : -1.0) * 0.008  // above the measured noise floor
            XCTAssertNil(d.add(Acceleration(x: rest.x + jitter, y: rest.y - jitter, z: rest.z + jitter)))
        }
    }

    func testBeingPickedUpTriggersOnce() {
        var d = detector()
        let lifted = Acceleration(x: 0.1, y: -0.3, z: -1.1)
        let reports = (0..<100).compactMap { _ in d.add(lifted) }
        XCTAssertEqual(reports.count, 1)
        XCTAssertGreaterThan(reports[0], MotionSensitivity.medium.threshold)
    }

    func testNothingReportedDuringWarmUp() {
        var d = MotionDetector(sensitivity: .high)
        let wild = Acceleration(x: 2, y: 2, z: 2)
        for _ in 0..<(MotionDetector.warmUpSamples - 1) { XCTAssertNil(d.add(wild)) }
    }

    func testLidAngleParsesNineBits() {
        XCTAssertEqual(LidAngle(report: [1, 0x81, 0x00]), LidAngle(degrees: 129))
        XCTAssertEqual(LidAngle(report: [1, 0xFF, 0xFF])?.degrees, 511)
        XCTAssertNil(LidAngle(report: [1, 0x81]))
    }

    func testLidMovementPastThresholdTriggersOnce() {
        var d = LidAngleDetector()
        XCTAssertNil(d.add(LidAngle(degrees: 110)))
        XCTAssertNil(d.add(LidAngle(degrees: 113)))
        XCTAssertEqual(d.add(LidAngle(degrees: 104)), -6)
        XCTAssertNil(d.add(LidAngle(degrees: 60)))
    }
}
