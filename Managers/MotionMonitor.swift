// MotionMonitor.swift
// MacGuard - Anti-Theft Alarm for macOS

import Foundation
import IOKit
import IOKit.hid

/// Reads the accelerometer and lid-angle sensor of Apple Silicon MacBooks
/// (AppleSPUHIDDevice; no root needed) and feeds the pure detectors.
/// Sensor layout per github.com/olvvier/apple-silicon-accelerometer (MIT).
final class MotionMonitor {
    var onInput: (AlarmInput) -> Void = { _ in }

    private static let accelerometerMatch: [String: Int] = [kIOHIDPrimaryUsagePageKey: 0xFF00, kIOHIDPrimaryUsageKey: 3]
    private static let lidMatch: [String: Int] = [kIOHIDPrimaryUsagePageKey: 0x20, kIOHIDPrimaryUsageKey: 138]

    static let hasAccelerometer = !devices(matching: accelerometerMatch).devices.isEmpty
    static let hasLidSensor = !devices(matching: lidMatch).devices.isEmpty

    private struct Accelerometer {
        let manager: IOHIDManager
        let buffer: UnsafeMutablePointer<UInt8>
        let driver: io_service_t?
        var detector: MotionDetector
    }

    private struct Lid {
        let manager: IOHIDManager
        let device: IOHIDDevice
        let timer: Timer
        var detector = LidAngleDetector()
    }

    private var accelerometer: Accelerometer?
    private var lid: Lid?

    func start(motion sensitivity: MotionSensitivity?, lidAngle: Bool) {
        stop()
        if let sensitivity { startAccelerometer(sensitivity) }
        if lidAngle { startLidSensor() }
    }

    func stop() {
        if let accelerometer {
            IOHIDManagerUnscheduleFromRunLoop(accelerometer.manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerClose(accelerometer.manager, IOOptionBits(kIOHIDOptionsTypeNone))
            accelerometer.buffer.deallocate()
            if let driver = accelerometer.driver {
                Self.setDriver(driver, reporting: false)
                IOObjectRelease(driver)
            }
        }
        accelerometer = nil

        if let lid {
            lid.timer.invalidate()
            IOHIDManagerClose(lid.manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        lid = nil
    }

    // MARK: Accelerometer

    private func startAccelerometer(_ sensitivity: MotionSensitivity) {
        let (manager, devices) = Self.devices(matching: Self.accelerometerMatch)
        guard !devices.isEmpty else {
            logActivity(.system, "Motion trigger unavailable: no accelerometer")
            return
        }
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
        accelerometer = Accelerometer(manager: manager, buffer: buffer, driver: Self.wakeDriver(),
                                      detector: MotionDetector(sensitivity: sensitivity))
        let context = Unmanaged.passUnretained(self).toOpaque()
        for device in devices {
            IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, { context, _, _, _, _, report, length in
                guard let context else { return }
                Unmanaged<MotionMonitor>.fromOpaque(context).takeUnretainedValue()
                    .received(UnsafeRawBufferPointer(start: report, count: length))
            }, context)
        }
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        logActivity(.system, "Motion monitoring started (\(sensitivity.rawValue) sensitivity)")
    }

    private func received(_ report: UnsafeRawBufferPointer) {
        guard let sample = Acceleration(report: report),
              let deviation = accelerometer?.detector.add(sample) else { return }
        logActivity(.input, String(format: "Motion detected (%.3f g)", deviation))
        onInput(.intrusion(.motion))
    }

    /// The accelerometer reports only while its driver is powered and
    /// reporting. Only its own driver is touched: the other SPU drivers
    /// (lid, gyro, light) serve macOS. Their properties don't read back, so
    /// stopping switches reporting off rather than restoring a prior value.
    private static func wakeDriver() -> io_service_t? {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSPUHIDDriver"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        while case let service = IOIteratorNext(iterator), service != 0 {
            let page: Int? = IORegistry.property(kIOHIDPrimaryUsagePageKey, of: service)
            let usage: Int? = IORegistry.property(kIOHIDPrimaryUsageKey, of: service)
            if page == accelerometerMatch[kIOHIDPrimaryUsagePageKey], usage == accelerometerMatch[kIOHIDPrimaryUsageKey] {
                setDriver(service, reporting: true)
                return service
            }
            IOObjectRelease(service)
        }
        return nil
    }

    private static func setDriver(_ service: io_service_t, reporting: Bool) {
        let values = ["SensorPropertyReportingState": reporting ? 1 : 0,
                      "SensorPropertyPowerState": reporting ? 1 : 0,
                      "ReportInterval": reporting ? 10_000 : 0]
        for (key, value) in values {
            IORegistryEntrySetCFProperty(service, key as CFString, value as CFNumber)
        }
    }

    // MARK: Lid angle

    private func startLidSensor() {
        let (manager, devices) = Self.devices(matching: Self.lidMatch)
        guard let device = devices.first else {
            logActivity(.system, "Lid angle trigger unavailable: no lid sensor")
            return
        }
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.pollLid() }
        RunLoop.main.add(timer, forMode: .common)
        lid = Lid(manager: manager, device: device, timer: timer)
        pollLid()
        logActivity(.system, "Lid angle monitoring started")
    }

    private func pollLid() {
        guard let device = lid?.device else { return }
        var report = [UInt8](repeating: 0, count: 8)
        var length = CFIndex(report.count)
        guard IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &report, &length) == kIOReturnSuccess,
              let angle = LidAngle(report: Array(report.prefix(length))),
              let change = lid?.detector.add(angle) else { return }
        logActivity(.input, "Lid moved \(change)°")
        onInput(.intrusion(.lidMoved(degrees: change)))
    }

    private static func devices(matching: [String: Int]) -> (manager: IOHIDManager, devices: [IOHIDDevice]) {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>).map(Array.init) ?? []
        return (manager, devices)
    }
}
