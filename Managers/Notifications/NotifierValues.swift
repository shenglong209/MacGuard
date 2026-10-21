// NotifierValues.swift
// MacGuard - Anti-Theft Alarm for macOS

import Foundation

/// One `@`, dotted domain, nothing that would need quoting.
struct EmailAddress: Hashable, Codable {
    let value: String

    init?(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let local = parts.first, let domain = parts.last,
              !local.isEmpty, local.count <= 64,
              domain.contains("."), !domain.hasPrefix("."), !domain.hasSuffix("."), !domain.contains(".."),
              trimmed.count <= 254,
              trimmed.unicodeScalars.allSatisfy(Self.isAllowed) else { return nil }
        value = trimmed
    }

    private static func isAllowed(_ scalar: Unicode.Scalar) -> Bool {
        !CharacterSet.whitespacesAndNewlines.contains(scalar)
            && !CharacterSet.controlCharacters.contains(scalar)
            && !"\"'<>(),;:\\[]".unicodeScalars.contains(scalar)
    }
}

enum MessagesRecipient: Hashable {
    case phone(String)
    case appleID(EmailAddress)

    init?(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let email = EmailAddress(trimmed) {
            self = .appleID(email)
            return
        }
        // Phone: optional leading "+", then 7-15 digits; common separators dropped
        let separators = CharacterSet(charactersIn: " -().")
        let compact = String(String.UnicodeScalarView(trimmed.unicodeScalars.filter { !separators.contains($0) }))
        let digits = compact.hasPrefix("+") ? compact.dropFirst() : Substring(compact)
        guard (7...15).contains(digits.count),
              digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        self = .phone(compact)
    }

    var handle: String {
        switch self {
        case .phone(let number): return number
        case .appleID(let email): return email.value
        }
    }
}

struct ShortcutName: Hashable {
    let value: String

    init?(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 255,
              !trimmed.unicodeScalars.contains(where: { CharacterSet.newlines.contains($0) }),
              !trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else { return nil }
        value = trimmed
    }
}

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
