// AlarmMachine.swift
// MacGuard - Anti-Theft Alarm for macOS

import Foundation

/// Why the alarm was set off, parsed at the monitor boundary.
enum TriggerCause: Equatable {
    case input(IntrusionInput)
    case powerDisconnected
    case lidClosed

    var label: String {
        switch self {
        case .input(let input): return input.label
        case .powerDisconnected: return "power cable disconnected"
        case .lidClosed: return "lid closed"
        }
    }
}
