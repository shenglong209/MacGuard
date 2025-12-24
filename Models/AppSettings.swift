// AppSettings.swift
// MacGuard - Anti-Theft Alarm for macOS
// Created: 2025-12-18

import SwiftUI

/// Proximity distance presets for trusted device detection
enum ProximityDistance: String, CaseIterable, Identifiable {
    case near = "Near"      // ~1-2m
    case medium = "Medium"  // ~3-5m (default)
    case far = "Far"        // ~7-10m
    case custom = "Custom"  // User-defined

    var id: String { rawValue }

    /// RSSI threshold for device presence (signal stronger than this = nearby)
    /// For custom, returns a default - actual value comes from AppSettings
    var presentThreshold: Int {
        switch self {
        case .near: return -60
        case .medium: return -70
        case .far: return -80
        case .custom: return -70  // Default, overridden by AppSettings
        }
    }

    /// RSSI threshold for device away (signal weaker than this = away)
    /// For custom, returns a default - actual value comes from AppSettings
    var awayThreshold: Int {
        switch self {
        case .near: return -70
        case .medium: return -80
        case .far: return -95
        case .custom: return -80  // Default, overridden by AppSettings
        }
    }

    /// Human-readable description
    var description: String {
        switch self {
        case .near: return "~1-2 meters"
        case .medium: return "~3-5 meters"
        case .far: return "~7-10 meters"
        case .custom: return "User-defined"
        }
    }

    /// Presets only (excludes custom for picker display)
    static var presets: [ProximityDistance] {
        [.near, .medium, .far]
    }
}

/// Auto-arm trigger mode for multiple trusted devices
enum AutoArmMode: String, CaseIterable, Identifiable {
    case allDevicesAway = "all"   // Arm when ALL devices leave (default)
    case anyDeviceAway = "any"    // Arm when ANY device leaves

    var id: String { rawValue }

    /// Display label for UI
    var label: String {
        switch self {
        case .allDevicesAway: return "All devices leave"
        case .anyDeviceAway: return "Any device leaves"
        }
    }

    /// Short description for UI
    var description: String {
        switch self {
        case .allDevicesAway: return "More flexible - arm only when all trusted devices are away"
        case .anyDeviceAway: return "More secure - arm when any trusted device leaves"
        }
    }
}

/// Available alarm sounds
enum AlarmSound: String, CaseIterable, Identifiable {
    // Bundled sound
    case dontTouchMyMac = "Don't Touch My Mac"
    // System sounds
    case funk = "Funk"
    case basso = "Basso"
    case blow = "Blow"
    case bottle = "Bottle"
    case frog = "Frog"
    case glass = "Glass"
    case hero = "Hero"
    case morse = "Morse"
    case ping = "Ping"
    case pop = "Pop"
    case purr = "Purr"
    case sosumi = "Sosumi"
    case submarine = "Submarine"
    case tink = "Tink"
    // Custom file
    case custom = "Custom..."

    var id: String { rawValue }

    /// Sound file path
    var soundPath: String? {
        switch self {
        case .dontTouchMyMac:
            return ResourceBundle.url(forResource: "dont-touch-my-mac", withExtension: "mp3", subdirectory: "Resources")?.path
        case .custom:
            return nil
        default:
            return "/System/Library/Sounds/\(rawValue).aiff"
        }
    }

    /// Check if sound file exists
    var isAvailable: Bool {
        switch self {
        case .dontTouchMyMac:
            return ResourceBundle.url(forResource: "dont-touch-my-mac", withExtension: "mp3", subdirectory: "Resources") != nil
        case .custom:
            return true
        default:
            return FileManager.default.fileExists(atPath: soundPath ?? "")
        }
    }
}

/// App settings manager with UserDefaults persistence
class AppSettings: ObservableObject {
    static let shared = AppSettings()

    // MARK: - Logging Helper

    private func log(_ category: ActivityLogCategory, _ message: String) {
        Task { @MainActor in
            ActivityLogManager.shared.log(category, message)
        }
    }

    // MARK: - Published Settings

    @AppStorage("autoLockOnArm") var autoLockOnArm: Bool = false
    @AppStorage("alarmSound") private var alarmSoundRaw: String = AlarmSound.dontTouchMyMac.rawValue
    @AppStorage("alarmVolume") var alarmVolume: Double = 1.0
    @AppStorage("customSoundPath") var customSoundPath: String = ""
    @AppStorage("countdownDuration") var countdownDuration: Int = 3
    @AppStorage("lidCloseProtection") private var _lidCloseProtection: Bool = false
    @AppStorage("proximityDistance") private var proximityDistanceRaw: String = ProximityDistance.medium.rawValue
    @AppStorage("customDetectionRange") var customDetectionRange: Int = -65  // Single value, hysteresis auto-calculated
    @AppStorage("autoArmOnDeviceLeave") var autoArmOnDeviceLeave: Bool = false
    @AppStorage("autoArmGracePeriod") var autoArmGracePeriod: Int = 15
    @AppStorage("autoArmMode") private var autoArmModeRaw: String = AutoArmMode.allDevicesAway.rawValue

    /// Auto-arm trigger mode (all devices away vs any device away)
    var autoArmMode: AutoArmMode {
        get { AutoArmMode(rawValue: autoArmModeRaw) ?? .allDevicesAway }
        set {
            autoArmModeRaw = newValue.rawValue
            objectWillChange.send()
        }
    }

    /// Proximity distance for trusted device detection
    var proximityDistance: ProximityDistance {
        get { ProximityDistance(rawValue: proximityDistanceRaw) ?? .medium }
        set {
            proximityDistanceRaw = newValue.rawValue
            objectWillChange.send()
        }
    }

    /// Effective present threshold (considers custom setting)
    /// Hysteresis: nearby threshold is 5 dBm stronger than the detection range
    var effectivePresentThreshold: Int {
        if proximityDistance == .custom {
            return customDetectionRange + 5  // Stronger signal = nearby
        }
        return proximityDistance.presentThreshold
    }

    /// Effective away threshold (considers custom setting)
    /// Hysteresis: away threshold is 5 dBm weaker than the detection range
    var effectiveAwayThreshold: Int {
        if proximityDistance == .custom {
            return customDetectionRange - 5  // Weaker signal = away
        }
        return proximityDistance.awayThreshold
    }

    /// Lid close protection with pmset control
    var lidCloseProtection: Bool {
        get { _lidCloseProtection }
        set {
            if newValue && !_lidCloseProtection {
                // Enabling - ask for admin password
                if enableDisableSleep() {
                    _lidCloseProtection = true
                    objectWillChange.send()
                }
                // If failed, don't change the setting
            } else if !newValue && _lidCloseProtection {
                // Disabling - ask for admin password
                disableDisableSleep()
                _lidCloseProtection = false
                objectWillChange.send()
            }
        }
    }

    /// Enable pmset disablesleep (with admin prompt)
    private func enableDisableSleep() -> Bool {
        let script = """
        do shell script "pmset -a disablesleep 1" with administrator privileges
        """

        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            scriptObject.executeAndReturnError(&error)
            if error == nil {
                log(.system, "disablesleep enabled")
                return true
            } else {
                log(.system, "Failed to enable disablesleep: \(error ?? [:])")
            }
        }
        return false
    }

    /// Disable pmset disablesleep (with admin prompt)
    private func disableDisableSleep() {
        let script = """
        do shell script "pmset -a disablesleep 0" with administrator privileges
        """

        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            scriptObject.executeAndReturnError(&error)
            if error == nil {
                log(.system, "disablesleep disabled")
            } else {
                log(.system, "Failed to disable disablesleep: \(error ?? [:])")
            }
        }
    }

    /// Reset lid close protection on app exit (no admin prompt, silent)
    func resetLidCloseProtection() {
        guard _lidCloseProtection else { return }

        // Use silent reset without admin prompt (best effort)
        let script = """
        do shell script "pmset -a disablesleep 0" with administrator privileges
        """

        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            scriptObject.executeAndReturnError(&error)
            if error == nil {
                log(.system, "disablesleep reset on app exit")
            }
        }
        _lidCloseProtection = false
    }

    /// Selected alarm sound
    var alarmSound: AlarmSound {
        get { AlarmSound(rawValue: alarmSoundRaw) ?? .funk }
        set {
            alarmSoundRaw = newValue.rawValue
            objectWillChange.send()
        }
    }

    /// Get the actual sound file path (custom or system)
    var effectiveSoundPath: String? {
        if alarmSound == .custom {
            return customSoundPath.isEmpty ? nil : customSoundPath
        }
        return alarmSound.soundPath
    }

    /// Custom sound file name for display
    var customSoundName: String {
        guard !customSoundPath.isEmpty else { return "None" }
        return URL(fileURLWithPath: customSoundPath).lastPathComponent
    }

    private init() {}

    /// Preview the selected alarm sound
    func previewSound() {
        guard let path = effectiveSoundPath,
              FileManager.default.fileExists(atPath: path),
              let sound = NSSound(contentsOfFile: path, byReference: true) else {
            NSSound.beep()
            return
        }
        sound.volume = Float(alarmVolume)
        sound.play()
    }

    /// Select custom sound file via file picker
    func selectCustomSound() -> Bool {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .mp3, .wav, .aiff]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select an audio file for the alarm"

        if panel.runModal() == .OK, let url = panel.url {
            customSoundPath = url.path
            alarmSound = .custom
            objectWillChange.send()
            return true
        }
        return false
    }
}
