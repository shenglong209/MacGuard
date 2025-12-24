// TrustedDevice.swift
// MacGuard - Anti-Theft Alarm for macOS
// Created: 2025-12-18

import Foundation

/// Represents a trusted Bluetooth device for auto-disarm
/// Supports both BLE devices (iPhone, Watch) and Classic Bluetooth (AirPods, headphones)
struct TrustedDevice: Identifiable, Codable, Hashable {
    /// Unique device identifier (Bluetooth UUID for BLE, generated UUID for Classic BT)
    let id: UUID

    /// User-friendly device name
    var name: String

    /// Bluetooth address for Classic BT devices (e.g., "AA-BB-CC-DD-EE-FF")
    var bluetoothAddress: String?

    /// Whether this device uses Classic Bluetooth (vs BLE)
    var isClassicBluetooth: Bool

    /// Last measured RSSI value (signal strength) - runtime only, not persisted
    var lastRSSI: Int?

    /// Last time device was seen - runtime only, not persisted
    var lastSeen: Date?

    // Only persist id, name, bluetoothAddress, isClassicBluetooth
    enum CodingKeys: String, CodingKey {
        case id, name, bluetoothAddress, isClassicBluetooth
    }

    // MARK: - Computed Properties

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
        if lowered.contains("headphone") || lowered.contains("beats") { return "headphones" }
        return "iphone"
    }

    // MARK: - Initialization

    init(id: UUID, name: String, bluetoothAddress: String? = nil, isClassicBluetooth: Bool = false) {
        self.id = id
        self.name = name
        self.bluetoothAddress = bluetoothAddress
        self.isClassicBluetooth = isClassicBluetooth
    }

    // Custom decoder to handle legacy devices without bluetoothAddress
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        bluetoothAddress = try container.decodeIfPresent(String.self, forKey: .bluetoothAddress)
        isClassicBluetooth = try container.decodeIfPresent(Bool.self, forKey: .isClassicBluetooth) ?? false
    }
}
