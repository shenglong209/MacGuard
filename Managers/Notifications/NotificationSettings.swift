// NotificationSettings.swift
// MacGuard - Anti-Theft Alarm for macOS

import SwiftUI

/// Raw user input; only `notifier(for:)` turns it into a notifier.
struct NotifierDrafts: Equatable {
    var enabled: Set<NotifierID> = []
    var webhookURL = ""

    /// `nil` while the configuration is incomplete.
    func notifier(for id: NotifierID) -> (any Notifier)? {
        switch id {
        case .notificationCenter: return NotificationCenterNotifier()
        case .webhook: return WebhookURL(webhookURL).map { WebhookNotifier(endpoint: $0) }
        }
    }

    /// An enabled flag whose draft doesn't parse contributes nothing.
    func enabledNotifiers() -> [any Notifier] {
        NotifierID.allCases.filter(enabled.contains).compactMap(notifier(for:))
    }
}

/// Everything is off by default.
final class NotificationSettings: ObservableObject {
    static let shared = NotificationSettings()

    @AppStorage("notify.enabled") private var enabledRaw = ""
    @AppStorage("notify.includeArmed") var includeArmed = false
    @AppStorage("notify.webhook.url") var webhookURL = ""

    var drafts: NotifierDrafts {
        NotifierDrafts(
            enabled: Set(enabledRaw.split(separator: ",").compactMap { NotifierID(rawValue: String($0)) }),
            webhookURL: webhookURL
        )
    }

    var policy: AlertPolicy { AlertPolicy(includeArmed: includeArmed) }

    func enabledNotifiers() -> [any Notifier] { drafts.enabledNotifiers() }

    /// Turning on succeeds only while the configuration parses.
    func isEnabled(_ id: NotifierID) -> Bool {
        drafts.enabled.contains(id) && drafts.notifier(for: id) != nil
    }

    func setEnabled(_ id: NotifierID, _ on: Bool) {
        var ids = drafts.enabled
        if on {
            guard drafts.notifier(for: id) != nil else { return }
            ids.insert(id)
        } else {
            ids.remove(id)
        }
        enabledRaw = NotifierID.allCases.filter(ids.contains).map(\.rawValue).joined(separator: ",")
    }

    private init() {}
}
