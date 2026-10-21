// TrustedDevice.swift
// MacGuard - Anti-Theft Alarm for macOS
// Created: 2025-12-18

import Foundation

/// Equal by the six bytes, so case or separator differences can't split one device.
struct BluetoothAddress: Hashable, CustomStringConvertible {
    let bytes: [UInt8]
    /// As received, so persisted data reads the same in older builds
    let description: String

    init?(_ text: String) {
        let hex = Array(text.filter { $0 != "-" && $0 != ":" })
        // isHexDigit also rules out "+"/"-" signs that UInt8(_:radix:) accepts
        guard hex.count == 12, hex.allSatisfy(\.isHexDigit) else { return nil }
        var bytes: [UInt8] = []
        for i in stride(from: 0, to: 12, by: 2) {
            guard let byte = UInt8(String(hex[i...i + 1]), radix: 16) else { return nil }
            bytes.append(byte)
        }
        self.bytes = bytes
        self.description = text
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.bytes == rhs.bytes }
    func hash(into hasher: inout Hasher) { hasher.combine(bytes) }
}

/// Both Bluetooth stacks report "no reading" in-band as 0 or 127; those parse to nil.
struct RSSI: Hashable, Comparable, CustomStringConvertible {
    let dBm: Int

    init?(_ raw: Int) {
        guard raw != 0, raw != 127 else { return nil }
        dBm = raw
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.dBm < rhs.dBm }
    var description: String { "\(dBm) dBm" }
}

/// Persisted identity only; runtime observations live in `BluetoothProximityManager`.
struct TrustedDevice: Identifiable, Codable, Hashable {
    enum Transport: Hashable {
        /// Matched by `CBPeripheral.identifier` (== `TrustedDevice.id`)
        case ble
        /// Matched by IOBluetooth address
        case classic(address: BluetoothAddress)
    }

    /// Unique device identifier (Bluetooth UUID for BLE, generated UUID for Classic BT)
    let id: UUID

    /// User-friendly device name
    var name: String

    let transport: Transport

    // Persisted under the original keys so older builds can still read the data
    enum CodingKeys: String, CodingKey {
        case id, name, bluetoothAddress, isClassicBluetooth
    }

    // MARK: - Computed Properties

    var isClassicBluetooth: Bool {
        if case .classic = transport { return true }
        return false
    }

    var classicAddress: BluetoothAddress? {
        if case .classic(let address) = transport { return address }
        return nil
    }

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

    init(id: UUID, name: String, transport: Transport) {
        self.id = id
        self.name = name
        self.transport = transport
    }

    // MARK: - Codable

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        let isClassic = try container.decodeIfPresent(Bool.self, forKey: .isClassicBluetooth) ?? false
        let address = try container.decodeIfPresent(String.self, forKey: .bluetoothAddress)
            .flatMap(BluetoothAddress.init)
        if isClassic, let address {
            transport = .classic(address: address)
        } else {
            // Legacy "classic without an address" records were never detected;
            // as BLE they still aren't, and the array still decodes.
            transport = .ble
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(isClassicBluetooth, forKey: .isClassicBluetooth)
        try container.encodeIfPresent(classicAddress?.description, forKey: .bluetoothAddress)
    }
}
