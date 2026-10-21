// NotificationDispatcher.swift
// MacGuard - Anti-Theft Alarm for macOS

import Foundation

enum DeliveryResult: Equatable {
    case delivered(NotifierID)
    case failed(NotifierID, String)

    var notifier: NotifierID {
        switch self {
        case .delivered(let id), .failed(let id, _): return id
        }
    }
}

/// Delivers off the main actor, every notifier concurrently; one failure never affects another.
final class NotificationDispatcher {
    static let shared = NotificationDispatcher(attachments: { await IntruderCamera.shared.latestPhotos(for: $0) })

    private let notifiers: () -> [any Notifier]
    private let policy: () -> AlertPolicy
    private let attachments: (AlarmEvent) async -> [URL]
    private let log: (String) -> Void
    private let now: () -> Date
    private let host: String

    init(
        notifiers: @escaping () -> [any Notifier] = { NotificationSettings.shared.enabledNotifiers() },
        policy: @escaping () -> AlertPolicy = { NotificationSettings.shared.policy },
        attachments: @escaping (AlarmEvent) async -> [URL] = { _ in [] },
        log: @escaping (String) -> Void = { logActivity(.system, $0) },
        now: @escaping () -> Date = Date.init,
        host: String = Host.current().localizedName ?? "Mac"
    ) {
        self.notifiers = notifiers
        self.policy = policy
        self.attachments = attachments
        self.log = log
        self.now = now
        self.host = host
    }

    /// Reads the configuration synchronously, then delivers in a detached task.
    func handle(_ event: AlarmEvent) {
        let targets = notifiers()
        guard !targets.isEmpty,
              let alert = Alert.make(from: event, at: now(), host: host, policy: policy()) else { return }
        Task.detached(priority: .userInitiated) { [self] in
            _ = await deliver(alert, for: event, to: targets)
        }
    }

    func dispatch(_ event: AlarmEvent) async -> [DeliveryResult] {
        let targets = notifiers()
        guard !targets.isEmpty,
              let alert = Alert.make(from: event, at: now(), host: host, policy: policy()) else { return [] }
        return await deliver(alert, for: event, to: targets)
    }

    func sendTest(via notifier: any Notifier) async -> DeliveryResult {
        await deliver(Alert.test(at: now(), host: host), for: nil, to: [notifier]).first
            ?? .failed(notifier.id, "not sent")
    }

    private func deliver(_ alert: Alert, for event: AlarmEvent?, to targets: [any Notifier]) async -> [DeliveryResult] {
        var alert = alert
        if let event { alert.attachments = await attachments(event) }
        let outgoing = alert

        let results = await withTaskGroup(of: DeliveryResult.self) { group in
            for notifier in targets {
                group.addTask {
                    do {
                        try await notifier.send(outgoing)
                        return .delivered(notifier.id)
                    } catch {
                        return .failed(notifier.id, error.localizedDescription)
                    }
                }
            }
            return await group.reduce(into: [DeliveryResult]()) { $0.append($1) }
        }

        for result in results {
            switch result {
            case .delivered(let id):
                log("Notification sent via \(id.displayName) (\(alert.kind.rawValue))")
            case .failed(let id, let reason):
                log("Notification via \(id.displayName) failed: \(reason)")
            }
        }
        return results.sorted { $0.notifier < $1.notifier }
    }
}
