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

    /// RSSI threshold for "nearby" detection (-70 dBm ≈ 3-5m)
    static let rssiThreshold: Int = -60

    /// SF Symbol icon based on device name
    var icon: String {
        Self.icon(for: name)
    }

    /// Get SF Symbol icon for a device name
    static func icon(for name: String) -> String {
        let lowered = name.lowercased()
        if lowered.contains("iphone") { return "iphone" }
        if lowered.contains("watch") { return "applewatch" }
        if lowered.contains("ipad") { return "ipad" }
        if lowered.contains("mac") { return "laptopcomputer" }
        if lowered.contains("airpods") { return "airpodspro" }
        return "iphone"
    }

    // MARK: - Initialization

    init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }
}
