// TrustedDevice.swift
// MacGuard - Anti-Theft Alarm for macOS
// Created: 2025-12-18

import Foundation

/// Represents a trusted Bluetooth device for auto-disarm
struct TrustedDevice: Identifiable, Codable, Hashable {
    /// Unique device identifier (Bluetooth UUID)
    let id: UUID

    /// User-friendly device name
    var name: String

    /// Last measured RSSI value (signal strength)
    var lastRSSI: Int?

    /// Last time device was seen
    var lastSeen: Date?

    // MARK: - Computed Properties

    /// Whether device is considered nearby based on RSSI threshold
    /// -50 dBm ≈ 1m distance (validated setting)
    var isNearby: Bool {
        guard let rssi = lastRSSI else { return false }
        return rssi > TrustedDevice.rssiThreshold
    }

    /// RSSI threshold for "nearby" detection (-50 dBm ≈ 1m)
    static let rssiThreshold: Int = -50

    // MARK: - Initialization

    init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }
}
