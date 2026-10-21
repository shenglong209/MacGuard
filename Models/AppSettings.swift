// AppSettings.swift
// MacGuard - Anti-Theft Alarm for macOS
// Created: 2025-12-18

import AVFoundation
import SwiftUI

/// Proximity distance presets for trusted device detection
enum ProximityDistance: String, CaseIterable, Identifiable {
    case near = "Near"      // ~1-2m
    case medium = "Medium"  // ~3-5m (default)
    case far = "Far"        // ~7-10m
    case custom = "Custom"  // User-defined

    var id: String { rawValue }

    func thresholds(customDetectionRange: Int) -> ProximityThresholds {
        switch self {
        case .near: return ProximityThresholds(present: -60, away: -70)
        case .medium: return ProximityThresholds(present: -70, away: -80)
        case .far: return ProximityThresholds(present: -80, away: -95)
        case .custom:
            let center = Self.clampedCustomRange(customDetectionRange)
            return ProximityThresholds(present: center + 5, away: center - 5)
        }
    }

    static let customRange: ClosedRange<Int> = -100 ... -55

    static func clampedCustomRange(_ raw: Int) -> Int {
        min(max(raw, customRange.lowerBound), customRange.upperBound)
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

    var file: PlayableSound? {
        switch self {
        case .dontTouchMyMac:
            return ResourceBundle.url(forResource: "dont-touch-my-mac", withExtension: "mp3", subdirectory: "Resources")
                .flatMap(PlayableSound.init(url:))
        case .custom:
            return nil
        default:
            return PlayableSound(url: URL(fileURLWithPath: "/System/Library/Sounds/\(rawValue).aiff"))
        }
    }

    /// Computed once: each check opens the file.
    static let offered: [AlarmSound] = allCases.filter { $0 == .custom || $0.file != nil }
}

/// A file `AVAudioPlayer` opens, with non-zero length, so a moved or corrupt file can't reach the alarm.
struct PlayableSound: Equatable {
    let url: URL

    init?(url: URL) {
        guard let player = try? AVAudioPlayer(contentsOf: url), player.duration > 0 else { return nil }
        self.url = url
    }
}

enum CountdownDuration: Int, CaseIterable, Identifiable {
    case immediate = 0
    case s3 = 3, s5 = 5, s10 = 10, s15 = 15, s30 = 30

    static let `default` = CountdownDuration.s3

    var id: Int { rawValue }

    var countdown: Countdown? { Countdown(seconds: rawValue) }

    var label: String { self == .immediate ? "Immediately" : "\(rawValue) seconds" }
}

/// Lets the owner walk away, and keeps the arming keystroke from being an intrusion.
enum ExitDelay: Int, CaseIterable, Identifiable {
    case s1 = 1, s5 = 5, s10 = 10, s30 = 30

    static let `default` = ExitDelay.s1

    var id: Int { rawValue }
    var seconds: TimeInterval { TimeInterval(rawValue) }
    var label: String { rawValue == 1 ? "1 second" : "\(rawValue) seconds" }
}

enum GracePeriod: Int, CaseIterable, Identifiable {
    case s5 = 5, s10 = 10, s15 = 15, s30 = 30, s60 = 60

    static let `default` = GracePeriod.s15

    var id: Int { rawValue }
    var seconds: TimeInterval { TimeInterval(rawValue) }
    var label: String { "\(rawValue) sec" }
}

/// A near-silent alarm is not offered.
struct AlarmVolume: Equatable {
    static let range: ClosedRange<Double> = 0.5...1.0

    let value: Double

    init(clamping raw: Double) {
        value = raw.isFinite ? min(max(raw, Self.range.lowerBound), Self.range.upperBound) : Self.range.upperBound
    }
}

/// App settings manager with UserDefaults persistence
class AppSettings: ObservableObject {
    static let shared = AppSettings()


    // MARK: - Published Settings

    @AppStorage("autoLockOnArm") var autoLockOnArm: Bool = false
    @AppStorage("alarmSound") private var alarmSoundRaw: String = AlarmSound.dontTouchMyMac.rawValue
    @AppStorage("alarmVolume") private var alarmVolumeRaw: Double = 1.0
    @AppStorage("customSoundPath") private var customSoundPath: String = ""
    // Enums parse in AppStorage itself: an unoffered stored value reads as the default.
    @AppStorage("countdownDuration") var countdownDuration: CountdownDuration = .default
    @AppStorage("lidCloseProtection") private var _lidCloseProtection: Bool = false
    @AppStorage("proximityDistance") var proximityDistance: ProximityDistance = .medium
    @AppStorage("customDetectionRange") var customDetectionRange: Int = -65  // Single value, hysteresis auto-calculated
    @AppStorage("autoArmOnDeviceLeave") var autoArmOnDeviceLeave: Bool = false
    @AppStorage("exitDelay") var exitDelay: ExitDelay = .default
    @AppStorage("usbTriggerEnabled") var usbTriggerEnabled: Bool = true
    @AppStorage("motionTriggerEnabled") var motionTriggerEnabled: Bool = true
    @AppStorage("motionSensitivity") var motionSensitivity: MotionSensitivity = .medium
    @AppStorage("lidAngleTriggerEnabled") var lidAngleTriggerEnabled: Bool = true
    @AppStorage("networkTriggerEnabled") var networkTriggerEnabled: Bool = false
    @AppStorage("autoArmOnScreenLock") var autoArmOnScreenLock: Bool = false
    @AppStorage("autoArmGracePeriod") var autoArmGracePeriod: GracePeriod = .default
    @AppStorage("autoArmMode") var autoArmMode: AutoArmMode = .allDevicesAway

    var alarmVolume: Double {
        get { AlarmVolume(clamping: alarmVolumeRaw).value }
        set { alarmVolumeRaw = AlarmVolume(clamping: newValue).value }
    }

    var proximityThresholds: ProximityThresholds {
        proximityDistance.thresholds(customDetectionRange: customDetectionRange)
    }

    /// Enabling only sticks if the admin prompt succeeds; disabling always clears it.
    var lidCloseProtection: Bool {
        get { _lidCloseProtection }
        set {
            guard newValue != _lidCloseProtection else { return }
            if setDisableSleep(newValue) || !newValue { _lidCloseProtection = newValue }
        }
    }

    /// On quit. pmset needs root, so this prompts for an admin password too.
    func resetLidCloseProtection() {
        guard _lidCloseProtection else { return }
        _ = setDisableSleep(false)
        _lidCloseProtection = false
    }

    private func setDisableSleep(_ on: Bool) -> Bool {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: "do shell script \"pmset -a disablesleep \(on ? 1 : 0)\" with administrator privileges") else { return false }
        script.executeAndReturnError(&error)
        if let error {
            logActivity(.system, "Failed to set disablesleep \(on ? 1 : 0): \(error)")
            return false
        }
        logActivity(.system, "disablesleep \(on ? "enabled" : "disabled")")
        return true
    }

    /// `.custom` without a playable file parses to the default.
    var alarmSound: AlarmSound {
        get {
            let sound = AlarmSound(rawValue: alarmSoundRaw) ?? .dontTouchMyMac
            return sound == .custom && customSound == nil ? .dontTouchMyMac : sound
        }
        set { alarmSoundRaw = newValue.rawValue }
    }

    /// The stored path, parsed once ("" means none chosen).
    private var customSoundURL: URL? {
        customSoundPath.isEmpty ? nil : URL(fileURLWithPath: customSoundPath)
    }

    private var customSound: PlayableSound? { customSoundURL.flatMap(PlayableSound.init(url:)) }

    var customSoundUnavailable: Bool {
        alarmSoundRaw == AlarmSound.custom.rawValue && customSound == nil
    }

    /// `nil` only if even the bundled sound is missing (the caller beeps).
    var alarmSoundFile: PlayableSound? {
        (alarmSound == .custom ? customSound : alarmSound.file) ?? AlarmSound.dontTouchMyMac.file
    }

    /// Custom sound file name for display
    var customSoundName: String { customSoundURL?.lastPathComponent ?? "None" }

    private init() {}

    /// Plays it once, so it can be judged without arming.
    func chooseSound(_ sound: AlarmSound) {
        alarmSound = sound
        previewSound()
    }

    /// Preview the selected alarm sound
    func previewSound() {
        guard let file = alarmSoundFile,
              let sound = NSSound(contentsOf: file.url, byReference: true) else {
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
            guard PlayableSound(url: url) != nil else {
                logActivity(.system, "Custom sound rejected: '\(url.lastPathComponent)' is not playable audio")
                return false
            }
            customSoundPath = url.path
            alarmSound = .custom
            previewSound()
            return true
        }
        return false
    }
}
