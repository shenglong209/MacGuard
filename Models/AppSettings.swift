// AppSettings.swift
// MacGuard - Anti-Theft Alarm for macOS
// Created: 2025-12-18

import SwiftUI

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
            return Bundle.module.url(forResource: "dont-touch-my-mac", withExtension: "mp3", subdirectory: "Resources")?.path
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
            return Bundle.module.url(forResource: "dont-touch-my-mac", withExtension: "mp3", subdirectory: "Resources") != nil
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

    // MARK: - Published Settings

    @AppStorage("autoLockOnArm") var autoLockOnArm: Bool = true
    @AppStorage("alarmSound") private var alarmSoundRaw: String = AlarmSound.dontTouchMyMac.rawValue
    @AppStorage("alarmVolume") var alarmVolume: Double = 1.0
    @AppStorage("customSoundPath") var customSoundPath: String = ""

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
