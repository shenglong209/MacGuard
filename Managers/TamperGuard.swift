// TamperGuard.swift
// MacGuard - Anti-Theft Alarm for macOS

import AppKit
import Darwin
import Security
import ServiceManagement
import SwiftUI

/// Exists from `.armed` until stand down: one whose process is gone means MacGuard was killed.
struct ArmedMarker: Codable, Equatable {
    let trustedDeviceHasLeft: Bool
    let armedAt: Date
    let pid: Int32

    init(_ session: ArmSession, armedAt: Date, pid: Int32) {
        trustedDeviceHasLeft = session.trustedDeviceHasLeft
        self.armedAt = armedAt
        self.pid = pid
    }

    var session: ArmSession { ArmSession(trustedDeviceHasLeft: trustedDeviceHasLeft) }
}

enum LaunchDecision: Equatable {
    case normal
    case resumeAfterTamper(ArmSession)

    static func decide(markerData: Data?, isAlive: (Int32) -> Bool) -> LaunchDecision {
        guard let markerData else { return .normal }
        // Unreadable marker: fail closed, without proximity-disarm rights.
        guard let marker = try? TamperGuard.decoder.decode(ArmedMarker.self, from: markerData) else {
            return .resumeAfterTamper(ArmSession(trustedDeviceHasLeft: false))
        }
        return isAlive(marker.pid) ? .normal : .resumeAfterTamper(marker.session)
    }
}

enum WatchdogStatus: Equatable {
    case off
    case active
    /// Allow MacGuard in System Settings > Login Items.
    case needsApproval
    case unavailable(String)

    init(enabled: Bool, service: SMAppService.Status, registrationError: String?) {
        guard enabled else { self = .off; return }
        if let registrationError { self = .unavailable(registrationError); return }
        switch service {
        case .enabled: self = .active
        case .requiresApproval: self = .needsApproval
        case .notRegistered: self = .unavailable("Not registered")
        case .notFound: self = .unavailable("Launch agent missing from app bundle")
        @unknown default: self = .unavailable("Unknown status")
        }
    }
}

/// The app writes `ArmedMarker` while armed; a KeepAlive launchd agent (this binary
/// with `--watchdog`) relaunches it when the marker's process is gone.
@MainActor
final class TamperGuard: ObservableObject {
    static let shared = TamperGuard()

    static let agentPlistName = "com.shenglong.macguard.watchdog.plist"

    nonisolated static let encoder = JSONEncoder()
    nonisolated static let decoder = JSONDecoder()

    @AppStorage("tamperProtection") private var enabledRaw = true
    @AppStorage("watchdogRegisteredCode") private var registeredCode = ""
    @Published private(set) var status: WatchdogStatus = .off
    private var registrationError: String?

    private var agent: SMAppService { SMAppService.agent(plistName: Self.agentPlistName) }

    private init() {}

    var isEnabled: Bool {
        get { enabledRaw }
        set {
            enabledRaw = newValue
            if !newValue { clear() }
            syncAgent()
        }
    }

    // MARK: Marker

    nonisolated static var markerURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("MacGuard/armed-session", isDirectory: false)
    }

    func persist(_ session: ArmSession) {
        guard isEnabled else { return }
        let marker = ArmedMarker(session, armedAt: Date(), pid: getpid())
        do {
            try FileManager.default.createDirectory(at: Self.markerURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try Self.encoder.encode(marker).write(to: Self.markerURL, options: .atomic)
        } catch {
            logActivity(.system, "Failed to write armed marker: \(error.localizedDescription)")
        }
    }

    func clear() {
        try? FileManager.default.removeItem(at: Self.markerURL)
    }

    func launchDecision() -> LaunchDecision {
        guard isEnabled else { clear(); return .normal }
        let data = try? Data(contentsOf: Self.markerURL)
        let me = getpid()
        return LaunchDecision.decide(markerData: data) { $0 != me && Self.isMacGuardProcess($0) }
    }

    // MARK: Watchdog agent

    func syncAgent() {
        registrationError = nil
        do {
            if isEnabled {
                // launchd pins the agent to the registering signature; after a
                // rebuild it refuses to start it (EX_CONFIG) while still `.enabled`.
                let code = Self.ownCodeHash ?? ""
                if agent.status == .enabled && registeredCode != code {
                    logActivity(.system, "App signature changed - re-registering tamper watchdog")
                    try agent.unregister()
                }
                if agent.status != .enabled {
                    try agent.register()
                    registeredCode = code
                }
            } else if agent.status == .enabled || agent.status == .requiresApproval {
                try agent.unregister()
            }
        } catch {
            registrationError = error.localizedDescription
            logActivity(.system, "Tamper watchdog \(isEnabled ? "registration" : "removal") failed: \(error.localizedDescription)")
        }
        status = WatchdogStatus(enabled: isEnabled, service: agent.status, registrationError: registrationError)
    }

    // MARK: Process identity

    nonisolated static func isMacGuardProcess(_ pid: Int32) -> Bool {
        guard pid > 0, kill(pid, 0) == 0 || errno == EPERM else { return false }
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return false }
        let path = URL(fileURLWithPath: String(cString: buffer)).resolvingSymlinksInPath().path
        return path == ownExecutablePath
    }

    /// Code directory hash (hex), nil when unsigned.
    nonisolated static let ownCodeHash: String? = {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var info: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, [], &info) == errSecSuccess,
              let unique = (info as? [String: Any])?[kSecCodeInfoUnique as String] as? Data else { return nil }
        return unique.map { String(format: "%02x", $0) }.joined()
    }()

    nonisolated static var ownExecutablePath: String? {
        Bundle.main.executableURL?.resolvingSymlinksInPath().path
    }
}

/// `MacGuard --watchdog`, run by the launchd agent. Never shows UI.
enum Watchdog {
    static let argument = "--watchdog"
    private static let pollInterval: TimeInterval = 2
    /// After a relaunch, give the new instance time to rewrite the marker.
    private static let relaunchBackoff: TimeInterval = 15

    static func run() -> Never {
        var nextAttempt = Date.distantPast
        let timer = Timer(timeInterval: pollInterval, repeats: true) { _ in
            guard Date() >= nextAttempt,
                  let data = try? Data(contentsOf: TamperGuard.markerURL) else { return }
            let decision = LaunchDecision.decide(markerData: data) { TamperGuard.isMacGuardProcess($0) }
            guard case .resumeAfterTamper = decision else { return }
            nextAttempt = Date().addingTimeInterval(relaunchBackoff)
            relaunchApp()
        }
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.run()
        exit(0)
    }

    private static func relaunchApp() {
        let configuration = NSWorkspace.OpenConfiguration()
        // The watchdog shares the bundle; force a real app instance.
        configuration.createsNewApplicationInstance = true
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            if let error {
                FileHandle.standardError.write(Data("MacGuard watchdog relaunch failed: \(error)\n".utf8))
            }
        }
    }
}
