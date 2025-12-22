// ActivityLogManager.swift
// MacGuard - Anti-Theft Alarm for macOS
// Created: 2025-12-22

import Foundation
import Combine

/// Singleton manager for activity logging throughout the app
@MainActor
class ActivityLogManager: ObservableObject {
    static let shared = ActivityLogManager()

    @Published private(set) var entries: [ActivityLogEntry] = []

    private let maxEntries = 500

    private init() {
        log(.system, "MacGuard started")
    }

    /// Add a new log entry
    func log(_ category: ActivityLogCategory, _ message: String) {
        let entry = ActivityLogEntry(
            timestamp: Date(),
            category: category,
            message: message
        )
        entries.insert(entry, at: 0)

        // Trim old entries
        while entries.count > maxEntries {
            entries.removeLast()
        }

        // Also print to console for debugging
        print("[MacGuard:\(category.rawValue)] \(message)")
    }

    /// Clear all log entries
    func clear() {
        entries.removeAll()
        log(.system, "Log cleared")
    }
}
