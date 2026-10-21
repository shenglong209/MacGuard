// TriggerParsingTests.swift
// MacGuard - Anti-Theft Alarm for macOS

import XCTest
@testable import MacGuard

final class TriggerParsingTests: XCTestCase {
    func testUSBNamePrefersProductString() {
        XCTAssertEqual(USBMonitor.productName(product: " SanDisk Ultra ", registryName: "USB3.0 Hub"), "SanDisk Ultra")
        XCTAssertEqual(USBMonitor.productName(product: "  ", registryName: "USB3.0 Hub"), "USB3.0 Hub")
        XCTAssertEqual(USBMonitor.productName(product: nil, registryName: nil), "Unknown USB device")
    }

    func testNetworkBaselineThenChanges() {
        let wifi = NetworkLink(name: "en0", kind: .wifi)
        let wired = NetworkLink(name: "en5", kind: .wired)
        XCTAssertFalse(NetworkMonitor.isChange(from: nil, to: [wifi]), "first snapshot is the baseline")
        XCTAssertFalse(NetworkMonitor.isChange(from: [wifi], to: [wifi]))
        XCTAssertTrue(NetworkMonitor.isChange(from: [wifi, wired], to: [wifi]), "cable pulled")
        XCTAssertTrue(NetworkMonitor.isChange(from: [wifi], to: []), "Wi-Fi dropped")
    }
}
