// USBMonitor.swift
// MacGuard - Anti-Theft Alarm for macOS

import Foundation
import IOKit
import IOKit.usb

/// Devices attached before monitoring starts are drained silently.
class USBMonitor {
    var onInput: (AlarmInput) -> Void = { _ in }

    private var session: (port: IONotificationPortRef, iterator: io_iterator_t)?

    /// Never empty.
    static func productName(product: String?, registryName: String?) -> String {
        for candidate in [product, registryName] {
            if let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
                return trimmed
            }
        }
        return "Unknown USB device"
    }

    func startMonitoring() {
        guard session == nil else { return }
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else {
            logActivity(.system, "USB monitoring unavailable")
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .commonModes)

        let callback: IOServiceMatchingCallback = { refcon, iterator in
            guard let refcon else { return }
            Unmanaged<USBMonitor>.fromOpaque(refcon).takeUnretainedValue().handleAttached(iterator)
        }
        var iterator = io_iterator_t()
        let status = IOServiceAddMatchingNotification(
            port,
            kIOFirstMatchNotification,
            IOServiceMatching("IOUSBHostDevice"),
            callback,
            Unmanaged.passUnretained(self).toOpaque(),
            &iterator
        )
        guard status == KERN_SUCCESS else {
            IONotificationPortDestroy(port)
            logActivity(.system, "USB monitoring failed: \(status)")
            return
        }
        // Arms the notification and skips devices that are already attached
        Self.drain(iterator) { _ in }
        session = (port, iterator)
        logActivity(.system, "Started monitoring USB devices")
    }

    func stopMonitoring() {
        guard let session else { return }
        IOObjectRelease(session.iterator)
        IONotificationPortDestroy(session.port)
        self.session = nil
        logActivity(.system, "Stopped monitoring USB devices")
    }

    private func handleAttached(_ iterator: io_iterator_t) {
        Self.drain(iterator) { service in
            var nameBuffer = [CChar](repeating: 0, count: MemoryLayout<io_name_t>.size)
            let registryName = IORegistryEntryGetName(service, &nameBuffer) == KERN_SUCCESS ? String(cString: nameBuffer) : nil
            let name = Self.productName(product: IORegistry.property(kUSBProductString, of: service), registryName: registryName)
            logActivity(.input, "USB device attached: \(name)")
            onInput(.intrusion(.usbDeviceAttached(name: name)))
        }
    }

    private static func drain(_ iterator: io_iterator_t, _ body: (io_object_t) -> Void) {
        while case let service = IOIteratorNext(iterator), service != 0 {
            body(service)
            IOObjectRelease(service)
        }
    }

    deinit {
        stopMonitoring()
    }
}
