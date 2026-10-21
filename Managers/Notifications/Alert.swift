// Alert.swift
// MacGuard - Anti-Theft Alarm for macOS

import Foundation

enum AlertKind: String, Codable {
    case armed, disarmed, countdown, alarm, test
}

/// Arming alerts are opt-in because they are routine and frequent.
struct AlertPolicy: Equatable {
    var includeArmed = false
}

struct Alert: Equatable, Codable {
    let kind: AlertKind
    let title: String
    let body: String
    let date: Date
    let host: String
    var attachments: [URL] = []

    static func make(from event: AlarmEvent, at date: Date, host: String, policy: AlertPolicy) -> Alert? {
        switch event {
        case .armed(let auto):
            guard policy.includeArmed else { return nil }
            let how = auto ? "automatically (trusted devices left)" : "manually"
            return Alert(kind: .armed, title: "MacGuard armed",
                         body: "\(host) was armed \(how).", date: date, host: host)
        case .disarmed(let reason):
            return Alert(kind: .disarmed, title: "MacGuard disarmed",
                         body: "\(host): \(reason).", date: date, host: host)
        case .countdownStarted(let cause, let seconds):
            return Alert(kind: .countdown, title: "MacGuard: intrusion detected",
                         body: "\(host): \(cause.label). Alarm sounds in \(seconds)s unless disarmed.",
                         date: date, host: host)
        case .alarmSounding(let cause):
            return Alert(kind: .alarm, title: "MacGuard ALARM",
                         body: "\(host): alarm is sounding (\(cause.label)).", date: date, host: host)
        }
    }

    static func test(at date: Date, host: String) -> Alert {
        Alert(kind: .test, title: "MacGuard test alert",
              body: "If you can read this, \(host) can reach you.", date: date, host: host)
    }
}
