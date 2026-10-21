// ActivityLogManager.swift
// MacGuard - Anti-Theft Alarm for macOS
// Created: 2025-12-22

import Foundation
import Combine
import AppKit

/// Singleton manager for activity logging throughout the app
@MainActor
class ActivityLogManager: ObservableObject {
    static let shared = ActivityLogManager()

    @Published private(set) var entries: [ActivityLogEntry] = []

    private let maxEntries = 500
    private let logFileURL: URL

    /// Coalesced: logging happens on every Bluetooth poll while armed.
    private var saveWorkItem: DispatchWorkItem?
    private let saveDelay: TimeInterval = 2.0

    private init() {
        // Store logs in Application Support directory
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let macGuardDir = appSupport.appendingPathComponent("MacGuard", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(at: macGuardDir, withIntermediateDirectories: true)

        logFileURL = macGuardDir.appendingPathComponent("activity-log.json")

        // Load existing logs
        loadFromDisk()

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
        if entries.count > maxEntries {
            entries.removeLast(entries.count - maxEntries)
        }

        scheduleSave()

        // Also print to console for debugging
        print("[MacGuard:\(category.rawValue)] \(message)")
    }

    /// Clear all log entries
    func clear() {
        entries.removeAll()
        log(.system, "Log cleared")
    }

    // MARK: - Persistence

    private func scheduleSave() {
        guard saveWorkItem == nil else { return }
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.flush() }
        }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + saveDelay, execute: item)
    }

    /// Call on app termination.
    func flush() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(entries)
            try data.write(to: logFileURL, options: .atomic)
        } catch {
            print("[ActivityLog] Failed to save: \(error.localizedDescription)")
        }
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: logFileURL.path) else { return }

        do {
            let data = try Data(contentsOf: logFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            entries = try decoder.decode([ActivityLogEntry].self, from: data)
            print("[ActivityLog] Loaded \(entries.count) entries from disk")
        } catch {
            print("[ActivityLog] Failed to load: \(error.localizedDescription)")
        }
    }

    // MARK: - Export

    /// Export logs as JSON string for troubleshooting
    func exportAsJSON() -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(entries),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    /// Export logs as human-readable text
    func exportAsText() -> String {
        var lines: [String] = []
        lines.append("MacGuard Event Log")
        lines.append("Exported: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("Entries: \(entries.count)")
        lines.append(String(repeating: "-", count: 60))
        lines.append("")

        for entry in entries.reversed() {
            lines.append("[\(entry.formattedDate)] [\(entry.category.rawValue)] \(entry.message)")
        }

        return lines.joined(separator: "\n")
    }

    /// Get log file URL for sharing
    func getExportFileURL() -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let exportURL = tempDir.appendingPathComponent("MacGuard-EventLog-\(dateString()).txt")

        do {
            try exportAsText().write(to: exportURL, atomically: true, encoding: .utf8)
            return exportURL
        } catch {
            print("[ActivityLog] Failed to create export file: \(error.localizedDescription)")
            return nil
        }
    }

    /// Share logs via system share sheet
    func shareLogFile() {
        guard let exportURL = getExportFileURL() else { return }

        let picker = NSSharingServicePicker(items: [exportURL])
        if let window = NSApplication.shared.keyWindow,
           let contentView = window.contentView {
            picker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
        }
    }

    /// Copy logs to clipboard
    func copyToClipboard() {
        let text = exportAsText()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func dateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}
