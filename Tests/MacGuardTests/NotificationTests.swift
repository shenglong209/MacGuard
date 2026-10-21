// NotificationTests.swift
// MacGuard - Anti-Theft Alarm for macOS

import XCTest
@testable import MacGuard

final class NotifierValueTests: XCTestCase {
    func testWebhookURLRequiresHTTPS() {
        XCTAssertEqual(WebhookURL("https://ntfy.sh/topic")?.url.host, "ntfy.sh")
        XCTAssertNotNil(WebhookURL("HTTPS://example.com/hook"))
        for bad in ["http://ntfy.sh/topic", "ftp://example.com", "https://", "ntfy.sh/topic", "", "file:///etc/passwd"] {
            XCTAssertNil(WebhookURL(bad), bad)
        }
    }
}

final class AlertTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    func testDefaultPolicySkipsArmed() {
        XCTAssertNil(Alert.make(from: .armed(auto: false), at: date, host: "Mac", policy: AlertPolicy()))
        XCTAssertEqual(Alert.make(from: .armed(auto: true), at: date, host: "Mac",
                                  policy: AlertPolicy(includeArmed: true))?.kind, .armed)
    }

    func testIntrusionEventsAlwaysAlert() throws {
        let countdown = try XCTUnwrap(Alert.make(from: .countdownStarted(.input(.keyboard), seconds: 5),
                                                 at: date, host: "Laptop", policy: AlertPolicy()))
        XCTAssertEqual(countdown.kind, .countdown)
        XCTAssertEqual(countdown.body, "Laptop: keyboard. Alarm sounds in 5s unless disarmed.")

        let alarm = try XCTUnwrap(Alert.make(from: .alarmSounding(.lidClosed), at: date, host: "Laptop",
                                             policy: AlertPolicy()))
        XCTAssertEqual(alarm.kind, .alarm)
        XCTAssertTrue(alarm.body.contains("lid closed"))

        let disarmed = try XCTUnwrap(Alert.make(from: .disarmed(reason: "Disarmed via PIN"), at: date,
                                                host: "Laptop", policy: AlertPolicy()))
        XCTAssertEqual(disarmed.kind, .disarmed)
        XCTAssertEqual(disarmed.date, date)
    }

    func testWebhookPayloadCountsAttachmentsWithoutPaths() {
        var alert = Alert.test(at: date, host: "Mac")
        alert.attachments = [URL(fileURLWithPath: "/a.jpg"), URL(fileURLWithPath: "/b.jpg")]
        let payload = WebhookNotifier.payload(for: alert)
        XCTAssertEqual(payload.attachmentCount, 2)
        XCTAssertEqual(payload.title, alert.title)
    }
}

final class NotifierDraftsTests: XCTestCase {
    func testIncompleteDraftsYieldNoNotifier() {
        let drafts = NotifierDrafts(enabled: Set(NotifierID.allCases), webhookURL: "http://x.com")
        XCTAssertEqual(drafts.enabledNotifiers().map(\.id), [.notificationCenter],
                       "enabled but unparseable drafts must not become notifiers")
    }

    func testOnlyEnabledCompleteNotifiers() {
        let drafts = NotifierDrafts(enabled: [.webhook], webhookURL: "https://example.com/hook")
        XCTAssertEqual(drafts.enabledNotifiers().map(\.id), [.webhook])
        XCTAssertNotNil(drafts.notifier(for: .notificationCenter), "available but not enabled")
    }

    func testNothingEnabledByDefault() {
        XCTAssertTrue(NotifierDrafts().enabledNotifiers().isEmpty)
    }
}

final class NotificationDispatcherTests: XCTestCase {
    private final class Recorder: Notifier {
        let id: NotifierID
        let fails: Bool
        private let lock = NSLock()
        private var _sent: [Alert] = []
        var sent: [Alert] { lock.withLock { _sent } }

        init(_ id: NotifierID, fails: Bool = false) {
            self.id = id
            self.fails = fails
        }

        func send(_ alert: Alert) async throws {
            if fails { throw NotifierError(message: "boom") }
            lock.withLock { _sent.append(alert) }
        }
    }

    private func dispatcher(_ notifiers: [any Notifier], policy: AlertPolicy = AlertPolicy(),
                            attachments: [URL] = [], logged: @escaping (String) -> Void = { _ in }) -> NotificationDispatcher {
        NotificationDispatcher(notifiers: { notifiers }, policy: { policy },
                               attachments: { _ in attachments }, log: logged,
                               now: { Date(timeIntervalSince1970: 0) }, host: "TestMac")
    }

    func testFansOutToEveryNotifierAndIsolatesFailures() async {
        let center = Recorder(.notificationCenter), broken = Recorder(.webhook, fails: true)
        var logs: [String] = []
        let lock = NSLock()
        let results = await dispatcher([broken, center], logged: { line in lock.withLock { logs.append(line) } })
            .dispatch(.alarmSounding(.powerDisconnected))

        XCTAssertEqual(results, [.delivered(.notificationCenter), .failed(.webhook, "boom")])
        XCTAssertEqual(center.sent.first?.kind, .alarm)
        XCTAssertTrue(logs.contains("Notification via Webhook failed: boom"))
    }

    func testPolicyFilteredEventSendsNothing() async {
        let mail = Recorder(.notificationCenter)
        let results = await dispatcher([mail]).dispatch(.armed(auto: false))
        XCTAssertTrue(results.isEmpty)
        XCTAssertTrue(mail.sent.isEmpty)
    }

    func testAttachmentsAreAddedToEventAlerts() async {
        let mail = Recorder(.notificationCenter)
        let photo = URL(fileURLWithPath: "/tmp-free/intruder.jpg")
        _ = await dispatcher([mail], attachments: [photo]).dispatch(.countdownStarted(.input(.click), seconds: 3))
        XCTAssertEqual(mail.sent.first?.attachments, [photo])
    }

    func testTestAlertGoesOnlyToTheChosenNotifier() async {
        let mail = Recorder(.notificationCenter), other = Recorder(.webhook)
        let result = await dispatcher([mail, other]).sendTest(via: mail)
        XCTAssertEqual(result, .delivered(.notificationCenter))
        XCTAssertEqual(mail.sent.first?.kind, .test)
        XCTAssertTrue(other.sent.isEmpty)
    }
}
