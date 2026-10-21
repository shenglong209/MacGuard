// SettingsParsingTests.swift
// MacGuard - Anti-Theft Alarm for macOS

import XCTest
import Combine
@testable import MacGuard

final class SettingsParsingTests: XCTestCase {
    func testCountdownDurationMapsToCountdown() {
        XCTAssertNil(CountdownDuration.immediate.countdown)
        XCTAssertEqual(CountdownDuration.s5.countdown?.total, 5)
    }

    func testAlarmVolumeClamps() {
        XCTAssertEqual(AlarmVolume(clamping: 0).value, 0.5)
        XCTAssertEqual(AlarmVolume(clamping: 0.75).value, 0.75)
        XCTAssertEqual(AlarmVolume(clamping: 7).value, 1.0)
        XCTAssertEqual(AlarmVolume(clamping: .nan).value, 1.0)
    }
}

final class ProximityDistanceTests: XCTestCase {
    func testEveryDistanceHasAProperBand() {
        for distance in ProximityDistance.allCases {
            for raw in [-200, -100, -65, -55, 0] {
                let band = distance.thresholds(customDetectionRange: raw)
                XCTAssertGreaterThan(band.present, band.away, "\(distance) @ \(raw)")
            }
        }
    }

    func testCustomRangeIsClampedToTheSliderRange() {
        XCTAssertEqual(ProximityDistance.custom.thresholds(customDetectionRange: 0),
                       ProximityThresholds(present: -50, away: -60))
        XCTAssertEqual(ProximityDistance.custom.thresholds(customDetectionRange: -500),
                       ProximityThresholds(present: -95, away: -105))
    }
}

final class SettingsPublishingTests: XCTestCase {
    /// AlarmStateManager re-plans idle scanning on AppSettings.objectWillChange,
    /// which relies on @AppStorage publishing from inside an ObservableObject.
    func testEnumSettingChangePublishes() {
        let settings = AppSettings.shared
        let original = settings.exitDelay
        defer { settings.exitDelay = original }
        var fired = 0
        let subscription = settings.objectWillChange.sink { fired += 1 }
        settings.exitDelay = original == .s30 ? .s10 : .s30
        subscription.cancel()
        XCTAssertGreaterThan(fired, 0)
    }
}
