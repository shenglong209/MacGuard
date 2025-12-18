// AlarmState.swift
// MacGuard - Anti-Theft Alarm for macOS
// Created: 2025-12-18

import Foundation

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
