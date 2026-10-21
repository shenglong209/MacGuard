// Fixtures.swift
// MacGuard - Anti-Theft Alarm for macOS

@testable import MacGuard

extension AlarmEnvironment {
    /// The one place tests build an environment; defaults match the app's.
    static func fixture(
        countdown: Int = 3,
        autoLock: Bool = false,
        autoArm: Bool = false,
        mode: AutoArmMode = .allDevicesAway,
        devices: Bool = true,
        any: Bool = false,
        all: Bool = false,
        stable: Bool = true,
        usb: Bool = true,
        network: Bool = false,
        motion: Bool = true,
        lidAngle: Bool = true,
        lockArms: Bool = false,
        exitDelay: ExitDelay = .s1
    ) -> AlarmEnvironment {
        AlarmEnvironment(
            countdown: Countdown(seconds: countdown), autoLockOnArm: autoLock,
            autoArmEnabled: autoArm, autoArmMode: mode, hasTrustedDevices: devices,
            anyTrustedDeviceNearby: any, allTrustedDevicesNearby: all, bluetoothStable: stable,
            usbTriggerEnabled: usb, networkTriggerEnabled: network,
            motionTriggerEnabled: motion, lidAngleTriggerEnabled: lidAngle,
            autoArmOnScreenLock: lockArms, exitDelay: exitDelay
        )
    }
}
