// NotificationSettingsView.swift
// MacGuard - Anti-Theft Alarm for macOS

import SwiftUI

struct NotificationSettingsSection: View {
    @ObservedObject private var settings = NotificationSettings.shared
    @State private var testResults: [NotifierID: String] = [:]
    @State private var testing: Set<NotifierID> = []

    var body: some View {
        Section {
            ForEach(NotifierID.allCases) { id in
                notifierRow(id)
            }
            Toggle("Also notify when armed", isOn: $settings.includeArmed)
                .font(.callout)
        } header: {
            Label("Notifications", systemImage: "bell.badge")
        } footer: {
            Text("Sent on intrusion, alarm and disarm. Mail and Messages ask for permission to control those apps the first time.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func notifierRow(_ id: NotifierID) -> some View {
        let configured = settings.drafts.notifier(for: id) != nil
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Toggle(id.displayName, isOn: Binding(
                    get: { settings.isEnabled(id) },
                    set: { settings.setEnabled(id, $0) }
                ))
                .disabled(!configured)
                Spacer()
                Button(testing.contains(id) ? "Sending…" : "Send test") { sendTest(id) }
                    .buttonStyle(GlassSecondaryButtonStyle())
                    .disabled(!configured || testing.contains(id))
            }
            if let field = field(for: id) {
                TextField(field.placeholder, text: field.text)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)
                if !field.text.wrappedValue.isEmpty && !configured {
                    Text(field.invalidHint)
                        .font(.caption)
                        .foregroundColor(Theme.StateColor.triggered)
                }
            }
            if let result = testResults[id] {
                Text(result)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private struct Field {
        let placeholder: String
        let invalidHint: String
        let text: Binding<String>
    }

    private func field(for id: NotifierID) -> Field? {
        switch id {
        case .notificationCenter:
            return nil
        case .mail:
            return Field(placeholder: "you@example.com", invalidHint: "Enter a valid e-mail address",
                         text: $settings.mailTo)
        case .messages:
            return Field(placeholder: "+15551234567 or Apple ID e-mail",
                         invalidHint: "Enter a phone number (7-15 digits) or Apple ID e-mail",
                         text: $settings.messagesTo)
        case .shortcuts:
            return Field(placeholder: "Shortcut name", invalidHint: "Enter a single-line Shortcut name",
                         text: $settings.shortcutName)
        case .webhook:
            return Field(placeholder: "https://ntfy.sh/your-topic", invalidHint: "Enter an https:// URL",
                         text: $settings.webhookURL)
        }
    }

    private func sendTest(_ id: NotifierID) {
        guard let notifier = settings.drafts.notifier(for: id) else { return }
        testing.insert(id)
        testResults[id] = nil
        Task {
            let result = await NotificationDispatcher.shared.sendTest(via: notifier)
            testing.remove(id)
            switch result {
            case .delivered: testResults[id] = "Test sent"
            case .failed(_, let reason): testResults[id] = "Failed: \(reason)"
            }
        }
    }
}
