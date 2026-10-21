// Notifier.swift
// MacGuard - Anti-Theft Alarm for macOS

import Foundation

/// Also UserDefaults key stems, so stable.
enum NotifierID: String, CaseIterable, Identifiable, Comparable {
    case notificationCenter, webhook

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .notificationCenter: return "Notification Center"
        case .webhook: return "Webhook"
        }
    }

    static func < (a: NotifierID, b: NotifierID) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }
}

/// Exists only with a complete, parsed configuration.
protocol Notifier {
    var id: NotifierID { get }
    func send(_ alert: Alert) async throws
}

struct NotifierError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
