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
        request.httpBody = try Self.encoder.encode(Self.payload(for: alert))
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw NotifierError(message: "webhook returned HTTP \(code)")
        }
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}
