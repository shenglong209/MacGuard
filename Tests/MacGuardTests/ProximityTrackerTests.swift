// ProximityTrackerTests.swift
// MacGuard - Anti-Theft Alarm for macOS

import XCTest
@testable import MacGuard

private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)
private let medium = ProximityThresholds(present: -70, away: -80)

private func signal(_ dBm: Int) -> Observation {
    .signal(RSSI(dBm)!)
}

private extension ProximityTracker {
    mutating func feed(_ obs: Observation, at seconds: TimeInterval,
                       cooldown: Bool = false, lowPower: Bool = false) -> ProximityChange {
        observe(obs, at: t0.addingTimeInterval(seconds), thresholds: medium,
                lowPower: lowPower, recoveryCooldownActive: cooldown)
    }
}

final class ProximityTrackerTests: XCTestCase {
    func testHysteresisBand() {
        var tracker = ProximityTracker()
        // Inside the band (-80...-70) is not enough to become nearby
        XCTAssertEqual(tracker.feed(signal(-75), at: 0), .unchanged)
        XCTAssertEqual(tracker.proximity, .away)
        XCTAssertEqual(tracker.feed(signal(-70), at: 1), .becameNearby)
        // ...but is enough to stay nearby
        XCTAssertEqual(tracker.feed(signal(-79), at: 2), .unchanged)
        XCTAssertTrue(tracker.isNearby)
    }

    func testAwayRequiresSustainedWeakSignal() {
        var tracker = ProximityTracker()
        _ = tracker.feed(signal(-60), at: 0)
        // 2s after the last nearby-strength reading: debounced (3s window)
        XCTAssertEqual(tracker.feed(signal(-90), at: 2), .awayDebounced(sinceNearby: 2))
        XCTAssertTrue(tracker.isNearby)
        // Weak readings do not refresh the window, so it expires
        XCTAssertEqual(tracker.feed(signal(-90), at: 3.5), .becameAway)
        XCTAssertFalse(tracker.isNearby)
    }

    func testAwayDebounceLongerInLowPower() {
        var tracker = ProximityTracker()
        _ = tracker.feed(signal(-60), at: 0)
        XCTAssertEqual(tracker.feed(signal(-90), at: 5, lowPower: true), .awayDebounced(sinceNearby: 5))
        XCTAssertEqual(tracker.feed(signal(-90), at: 10.5, lowPower: true), .becameAway)
    }

    func testRecoveryCooldownBlocksAwayTransition() {
        var tracker = ProximityTracker()
        _ = tracker.feed(signal(-60), at: 0)
        XCTAssertEqual(tracker.feed(.disconnected, at: 60, cooldown: true), .awaySuppressedByCooldown)
        XCTAssertTrue(tracker.isNearby)
        XCTAssertEqual(tracker.feed(.disconnected, at: 61), .becameAway)
    }

    func testDisconnectedIsNeverNearbyWhateverTheThresholds() {
        // A custom range of -100 dBm puts the away threshold at -105, below the old -100 sentinel
        let veryFar = ProximityThresholds(present: -95, away: -105)
        var tracker = ProximityTracker()
        _ = tracker.observe(signal(-60), at: t0, thresholds: veryFar, lowPower: false, recoveryCooldownActive: false)
        let change = tracker.observe(.disconnected, at: t0 + 60, thresholds: veryFar,
                                     lowPower: false, recoveryCooldownActive: false)
        XCTAssertEqual(change, .becameAway)
    }

    func testConnectedWithoutSignalCountsAsNearby() {
        var tracker = ProximityTracker()
        XCTAssertEqual(tracker.feed(.connectedWithoutSignal, at: 0), .becameNearby)
    }

    func testBLEDisconnectDebounce() {
        var tracker = ProximityTracker()
        _ = tracker.feed(signal(-60), at: 0)
        XCTAssertTrue(tracker.shouldDebounceDisconnect(at: t0 + 4, lowPower: false))
        XCTAssertFalse(tracker.shouldDebounceDisconnect(at: t0 + 5, lowPower: false))
        XCTAssertTrue(tracker.shouldDebounceDisconnect(at: t0 + 14, lowPower: true))
    }

    func testRecoveryAssumptionOnlyTouchesObservedDevices() {
        var observed = ProximityTracker()
        _ = observed.feed(signal(-90), at: 0)
        observed.assumeNearbyForRecovery()
        XCTAssertTrue(observed.isNearby)

        var unseen = ProximityTracker()
        unseen.assumeNearbyForRecovery()
        XCTAssertEqual(unseen.proximity, .unobserved)
    }

    func testResetForScanForgetsReadingButKeepsDebounceHistory() {
        var tracker = ProximityTracker()
        _ = tracker.feed(signal(-60), at: 0)
        tracker.resetForScan()
        XCTAssertEqual(tracker.proximity, .unobserved)
        XCTAssertNil(tracker.lastObservation)
        XCTAssertTrue(tracker.shouldDebounceDisconnect(at: t0 + 1, lowPower: false))
    }
}

final class ClassicLinkTrackerTests: XCTestCase {
    func testFirstPollInitialises() {
        var link = ClassicLinkTracker()
        XCTAssertEqual(link.poll(isConnected: true, rssi: nil, at: t0, lowPower: false),
                       .observe(.connectedWithoutSignal, .initiallyConnected))
        var down = ClassicLinkTracker()
        XCTAssertEqual(down.poll(isConnected: false, rssi: nil, at: t0, lowPower: false),
                       .observe(.disconnected, .initiallyDisconnected))
    }

    func testDisconnectRightAfterChangeIsDebounced() {
        var link = ClassicLinkTracker()
        _ = link.poll(isConnected: true, rssi: nil, at: t0, lowPower: false)
        XCTAssertEqual(link.poll(isConnected: false, rssi: nil, at: t0 + 2, lowPower: false), .disconnectDebounced)
        XCTAssertEqual(link.poll(isConnected: false, rssi: nil, at: t0 + 6, lowPower: false),
                       .observe(.disconnected, .disconnected))
    }

    func testMissingSignalFallsBackAfterTimeout() {
        var link = ClassicLinkTracker()
        _ = link.poll(isConnected: true, rssi: nil, at: t0, lowPower: false)
        XCTAssertEqual(link.poll(isConnected: true, rssi: RSSI(-65), at: t0 + 1, lowPower: false),
                       .observe(signal(-65), nil))
        XCTAssertEqual(link.poll(isConnected: true, rssi: nil, at: t0 + 1.5, lowPower: false), ClassicLinkTracker.PollResult.none)
        XCTAssertEqual(link.poll(isConnected: true, rssi: nil, at: t0 + 2.5, lowPower: false),
                       .observe(.connectedWithoutSignal, nil))
    }
}

final class RecoveryCooldownTests: XCTestCase {
    func testAssumedPresenceVouchesForNobodyDuringCooldown() {
        var cooldown = RecoveryCooldown()
        XCTAssertTrue(cooldown.vouchesForPresence(true, at: t0))
        cooldown.start(at: t0)
        XCTAssertFalse(cooldown.vouchesForPresence(true, at: t0 + 14))
        XCTAssertTrue(cooldown.vouchesForPresence(true, at: t0 + 15))
        XCTAssertFalse(cooldown.vouchesForPresence(false, at: t0 + 60))
    }
}

final class BluetoothParsingTests: XCTestCase {
    func testRSSIUnavailableSentinels() {
        XCTAssertNil(RSSI(127))
        XCTAssertNil(RSSI(0))
        XCTAssertEqual(RSSI(-64)?.dBm, -64)
    }

    func testBluetoothAddressNormalisesCaseAndSeparators() throws {
        let a = try XCTUnwrap(BluetoothAddress("aa-bb-cc-dd-ee-ff"))
        XCTAssertEqual(a, BluetoothAddress("AA:BB:CC:DD:EE:FF"))
        XCTAssertEqual(a, BluetoothAddress("aabbccddeeff"))
        XCTAssertEqual(a.bytes, [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF])
        XCTAssertEqual(a.description, "aa-bb-cc-dd-ee-ff", "original text kept for persistence")
    }

    func testBluetoothAddressRejectsMalformed() {
        XCTAssertNil(BluetoothAddress(""))
        XCTAssertNil(BluetoothAddress("aa-bb-cc-dd-ee"))
        XCTAssertNil(BluetoothAddress("aa-bb-cc-dd-ee-gg"))
        XCTAssertNil(BluetoothAddress("+a-bb-cc-dd-ee-ff"))
    }

    func testTrustedDeviceLegacyDecodingAndRoundTrip() throws {
        let json = Data("""
        [{"id":"11111111-1111-1111-1111-111111111111","name":"AirPods","isClassicBluetooth":true,"bluetoothAddress":"aa-bb-cc-dd-ee-ff"},
         {"id":"22222222-2222-2222-2222-222222222222","name":"Phone","isClassicBluetooth":false},
         {"id":"33333333-3333-3333-3333-333333333333","name":"NoAddress","isClassicBluetooth":true},
         {"id":"44444444-4444-4444-4444-444444444444","name":"Oldest"}]
        """.utf8)
        let devices = try JSONDecoder().decode([TrustedDevice].self, from: json)
        let address = try XCTUnwrap(BluetoothAddress("aa-bb-cc-dd-ee-ff"))
        XCTAssertEqual(devices.map(\.transport), [.classic(address: address), .ble, .ble, .ble])

        let encoded = try JSONEncoder().encode(devices)
        XCTAssertEqual(try JSONDecoder().decode([TrustedDevice].self, from: encoded), devices)
        let first = try XCTUnwrap((try JSONSerialization.jsonObject(with: encoded) as? [[String: Any]])?.first)
        XCTAssertEqual(first["bluetoothAddress"] as? String, "aa-bb-cc-dd-ee-ff")
        XCTAssertEqual(first["isClassicBluetooth"] as? Bool, true)
    }
}
