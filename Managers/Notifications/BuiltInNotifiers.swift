// BuiltInNotifiers.swift
// MacGuard - Anti-Theft Alarm for macOS

import Foundation
import UserNotifications

struct NotificationCenterNotifier: Notifier {
    let id = NotifierID.notificationCenter

    func send(_ alert: Alert) async throws {
        // UNUserNotificationCenter traps outside an app bundle (e.g. `swift run`)
        guard Bundle.main.bundleIdentifier != nil, Bundle.main.bundleURL.pathExtension == "app" else {
            throw NotifierError(message: "Notification Center needs the packaged MacGuard.app")
        }
        let center = UNUserNotificationCenter.current()
        guard try await center.requestAuthorization(options: [.alert, .sound]) else {
            throw NotifierError(message: "notifications not allowed in System Settings")
        }
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = .default
        content.attachments = alert.attachments.compactMap {
            try? UNNotificationAttachment(identifier: $0.lastPathComponent, url: $0)
        }
        try await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}

struct MailNotifier: Notifier {
    let id = NotifierID.mail
    let recipient: EmailAddress

    func send(_ alert: Alert) async throws {
        try await ProcessRunner.osascript([
            "on run argv",
            "set theRecipient to item 1 of argv",
            "tell application \"Mail\"",
            "set msg to make new outgoing message with properties {subject:(item 2 of argv), content:(item 3 of argv) & return, visible:false}",
            "tell msg to make new to recipient at end of to recipients with properties {address:theRecipient}",
            "repeat with i from 4 to count of argv",
            "tell content of msg to make new attachment with properties {file name:(POSIX file (item i of argv))} at after last paragraph",
            "end repeat",
            "send msg",
            "end tell",
            "end run",
        ], arguments: [recipient.value, alert.title, alert.body] + alert.attachments.map(\.path))
    }
}

struct MessagesNotifier: Notifier {
    let id = NotifierID.messages
    let recipient: MessagesRecipient

    func send(_ alert: Alert) async throws {
        try await ProcessRunner.osascript([
            "on run argv",
            "tell application \"Messages\"",
            "set svc to 1st account whose service type = iMessage",
            "set target to participant (item 1 of argv) of svc",
            "send (item 2 of argv) to target",
            "repeat with i from 3 to count of argv",
            "send (POSIX file (item i of argv)) to target",
            "end repeat",
            "end tell",
            "end run",
        ], arguments: [recipient.handle, "\(alert.title)\n\(alert.body)"] + alert.attachments.map(\.path))
    }
}

/// The alert goes in as JSON, so a Shortcut can forward it anywhere.
struct ShortcutsNotifier: Notifier {
    let id = NotifierID.shortcuts
    let shortcut: ShortcutName

    func send(_ alert: Alert) async throws {
        let directory = try Self.inputDirectory()
        let input = directory.appendingPathComponent("alert-\(UUID().uuidString).json")
        try Self.encoder.encode(alert).write(to: input, options: .atomic)
        defer { try? FileManager.default.removeItem(at: input) }
        try await ProcessRunner.run("/usr/bin/shortcuts", ["run", shortcut.value, "--input-path", input.path])
    }

    /// ~/Library/Application Support/MacGuard/notifications (owner-only).
    private static func inputDirectory() throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
        let directory = support.appendingPathComponent("MacGuard/notifications", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        return directory
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}

/// Attachments are not uploaded; only their count is sent.
struct WebhookNotifier: Notifier {
    let id = NotifierID.webhook
    let endpoint: WebhookURL
    var session: URLSession = .shared

    struct Payload: Codable, Equatable {
        let kind: AlertKind
        let title: String
        let body: String
        let date: Date
        let host: String
        let attachmentCount: Int
    }

    static func payload(for alert: Alert) -> Payload {
        Payload(kind: alert.kind, title: alert.title, body: alert.body, date: alert.date,
                host: alert.host, attachmentCount: alert.attachments.count)
    }

    func send(_ alert: Alert) async throws {
        var request = URLRequest(url: endpoint.url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try ShortcutsNotifier.encoder.encode(Self.payload(for: alert))
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw NotifierError(message: "webhook returned HTTP \(code)")
        }
    }
}
