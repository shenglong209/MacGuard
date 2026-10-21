// NotifierValues.swift
// MacGuard - Anti-Theft Alarm for macOS

import Foundation

/// Plain `http` is not representable: alerts must not travel in clear text.
struct WebhookURL: Hashable {
    let url: URL

    init?(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty else { return nil }
        self.url = url
    }
}
