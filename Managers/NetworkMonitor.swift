// NetworkMonitor.swift
// MacGuard - Anti-Theft Alarm for macOS

import Foundation
import Network

struct NetworkLink: Hashable {
    enum Kind: Hashable { case wifi, wired }
    let name: String
    let kind: Kind
}

/// Reports when the set of Wi-Fi / wired links in use changes.
class NetworkMonitor {
    var onInput: (AlarmInput) -> Void = { _ in }

    private var monitor: NWPathMonitor?
    private var baseline: Set<NetworkLink>?

    /// Loopback, VPN tunnels and cellular are not physical tampering signals.
    static func links(of path: NWPath) -> Set<NetworkLink> {
        guard path.status == .satisfied else { return [] }
        return Set(path.availableInterfaces.compactMap { interface in
            switch interface.type {
            case .wifi: return NetworkLink(name: interface.name, kind: .wifi)
            case .wiredEthernet: return NetworkLink(name: interface.name, kind: .wired)
            default: return nil
            }
        })
    }

    static func isChange(from baseline: Set<NetworkLink>?, to current: Set<NetworkLink>) -> Bool {
        guard let baseline else { return false }
        return baseline != current
    }

    func startMonitoring() {
        guard monitor == nil else { return }
        // NWPathMonitor cannot be restarted after cancel
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let current = Self.links(of: path)
            if Self.isChange(from: self.baseline, to: current) {
                logActivity(.system, "Network links changed")
                self.onInput(.intrusion(.networkChanged))
            }
            self.baseline = current
        }
        monitor.start(queue: .main)
        self.monitor = monitor
        logActivity(.system, "Started monitoring network links")
    }

    func stopMonitoring() {
        guard let monitor else { return }
        monitor.cancel()
        self.monitor = nil
        baseline = nil
        logActivity(.system, "Stopped monitoring network links")
    }

    deinit {
        monitor?.cancel()
    }
}
