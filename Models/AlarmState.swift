// AlarmState.swift
// MacGuard - Anti-Theft Alarm for macOS
// Created: 2025-12-18

import Foundation

struct ArmSession: Equatable {
    /// Only then may a device's return disarm: a phone in your pocket at a
    /// manual arm must not disarm a moment later.
    var trustedDeviceHasLeft: Bool
}

/// `remaining` is always in `1...total`; an expired countdown is `.alarming`.
struct Countdown: Equatable {
    let total: Int
    private(set) var remaining: Int

    /// `nil` when the alarm should sound immediately.
    init?(seconds: Int) {
        guard seconds > 0 else { return nil }
        total = seconds
        remaining = seconds
    }

    func ticked() -> Countdown? {
        guard remaining > 1 else { return nil }
        var next = self
        next.remaining -= 1
        return next
    }

    var progress: Double { Double(remaining) / Double(total) }
}

/// Represents the current state of the alarm system
enum AlarmState: String, Equatable {
    /// App running, theft mode OFF
    case idle
    /// Theft mode ON, monitoring for unauthorized input
    case armed
    /// Intrusion detected, countdown active before alarm
    case triggered
    /// Alarm is actively playing
    case alarming

    var description: String {
        switch self {
        case .idle: return "Idle"
        case .armed: return "Armed"
        case .triggered: return "Triggered"
        case .alarming: return "Alarming"
        }
    }

    var menuBarIcon: String {
        switch self {
        case .idle: return "lock.shield"
        case .armed: return "lock.shield.fill"
        case .triggered: return "exclamationmark.shield.fill"
        case .alarming: return "bell.badge.fill"
        }
    }
}
