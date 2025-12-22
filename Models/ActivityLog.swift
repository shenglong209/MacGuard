// ActivityLog.swift
// MacGuard - Anti-Theft Alarm for macOS
// Created: 2025-12-22

import Foundation

/// Log entry category for filtering and display
enum ActivityLogCategory: String, CaseIterable {
    case system = "System"
    case armed = "Armed"
    case disarmed = "Disarmed"
    case trigger = "Trigger"
    case alarm = "Alarm"
    case bluetooth = "Bluetooth"
    case input = "Input"
    case power = "Power"

    var icon: String {
        switch self {
        case .system: return "gearshape"
        case .armed: return "lock.shield.fill"
        case .disarmed: return "lock.open"
        case .trigger: return "exclamationmark.triangle"
        case .alarm: return "bell.badge.fill"
        case .bluetooth: return "antenna.radiowaves.left.and.right"
        case .input: return "keyboard"
        case .power: return "bolt"
        }
    }
}

/// Single activity log entry
struct ActivityLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let category: ActivityLogCategory
    let message: String

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    var formattedTime: String {
        Self.timeFormatter.string(from: timestamp)
    }

    var formattedDate: String {
        Self.dateFormatter.string(from: timestamp)
    }
}
