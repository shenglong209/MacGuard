// AlarmAudioManager.swift
// MacGuard - Anti-Theft Alarm for macOS
// Created: 2025-12-18

import AVFoundation
import Cocoa

/// Manages alarm audio playback at maximum volume
class AlarmAudioManager: ObservableObject {
    @Published var isPlaying = false

    private var audioPlayer: AVAudioPlayer?
    private var originalVolume: Float = 0.5
    private var beepTimer: Timer?
    private var volumeEnforcementTimer: Timer?
    private var isPrepared = false
    private var targetVolume: Float = 1.0

    // MARK: - Preparation

    /// Pre-load audio file so it's ready for instant playback
    func prepare() {
        guard !isPrepared else { return }

        let settings = AppSettings.shared
        if let soundPath = settings.effectiveSoundPath,
           FileManager.default.fileExists(atPath: soundPath) {
            do {
                audioPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: soundPath))
                audioPlayer?.numberOfLoops = -1
                audioPlayer?.volume = 1.0
                audioPlayer?.prepareToPlay()
                isPrepared = true
                print("[Alarm] Audio pre-loaded and ready")
            } catch {
                print("[Alarm] Failed to pre-load audio: \(error)")
            }
        }
    }

    /// Release pre-loaded audio
    func unprepare() {
        if !isPlaying {
            audioPlayer?.stop()
            audioPlayer = nil
            isPrepared = false
            print("[Alarm] Audio released")
        }
    }

    // MARK: - Playback

    /// Play the alarm sound at configured volume
    func playAlarm() {
        guard !isPlaying else { return }

        let settings = AppSettings.shared

        // Save original volume
        saveOriginalVolume()

        // Store target volume for enforcement
        targetVolume = Float(settings.alarmVolume)

        // Set system volume based on settings
        setSystemVolume(targetVolume)

        // Unmute if muted
        unmuteSpeaker()

        // Start volume enforcement timer to prevent muting
        startVolumeEnforcement()

        // Use pre-loaded player if available, otherwise load now
        if isPrepared, let player = audioPlayer {
            player.play()
            isPlaying = true
            print("[Alarm] Playing alarm sound (pre-loaded)")
        } else if let soundPath = settings.effectiveSoundPath,
           FileManager.default.fileExists(atPath: soundPath) {
            playAudioFile(URL(fileURLWithPath: soundPath))
        } else {
            // Fallback to system beep
            print("[Alarm] Alarm sound not found, using system beep")
            playSystemAlert()
        }
    }

    /// Stop the alarm and restore volume
    func stopAlarm() {
        // Stop volume enforcement first
        stopVolumeEnforcement()

        audioPlayer?.stop()
        audioPlayer = nil
        beepTimer?.invalidate()
        beepTimer = nil
        isPlaying = false
        isPrepared = false

        // Restore original volume
        setSystemVolume(originalVolume)

        print("[Alarm] Alarm stopped")
    }

    // MARK: - Volume Enforcement

    /// Start timer to continuously enforce volume (prevents muting via keyboard)
    private func startVolumeEnforcement() {
        stopVolumeEnforcement()
        volumeEnforcementTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            self?.enforceVolume()
        }
        print("[Alarm] Volume enforcement started")
    }

    private func stopVolumeEnforcement() {
        volumeEnforcementTimer?.invalidate()
        volumeEnforcementTimer = nil
    }

    /// Check and restore volume if user tries to mute
    private func enforceVolume() {
        guard isPlaying else { return }

        // Check if muted
        let muteScript = "output muted of (get volume settings)"
        if let result = runAppleScript(muteScript),
           result.trimmingCharacters(in: .whitespacesAndNewlines) == "true" {
            unmuteSpeaker()
            setSystemVolume(targetVolume)
            print("[Alarm] Mute blocked - volume restored")
        }

        // Check if volume lowered
        let volumeScript = "output volume of (get volume settings)"
        if let result = runAppleScript(volumeScript),
           let currentVolume = Int(result.trimmingCharacters(in: .whitespacesAndNewlines)) {
            let targetPercentage = Int(targetVolume * 100)
            if currentVolume < targetPercentage - 5 {
                setSystemVolume(targetVolume)
                print("[Alarm] Volume restored from \(currentVolume)% to \(targetPercentage)%")
            }
        }
    }

    // MARK: - Audio File Playback

    private func playAudioFile(_ url: URL) {
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.numberOfLoops = -1 // Loop forever
            audioPlayer?.volume = 1.0
            audioPlayer?.prepareToPlay() // Pre-load audio buffers
            audioPlayer?.play()
            isPlaying = true
            print("[Alarm] Playing alarm sound")
        } catch {
            print("[Alarm] Failed to play alarm: \(error)")
            playSystemAlert()
        }
    }

    // MARK: - System Volume Control

    private func saveOriginalVolume() {
        let script = """
        output volume of (get volume settings)
        """
        if let result = runAppleScript(script),
           let volume = Int(result.trimmingCharacters(in: .whitespacesAndNewlines)) {
            originalVolume = Float(volume) / 100.0
            print("[Alarm] Saved original volume: \(originalVolume)")
        }
    }

    private func setSystemVolume(_ volume: Float) {
        let percentage = Int(volume * 100)
        let script = "set volume output volume \(percentage)"
        runAppleScript(script)
        print("[Alarm] Set volume to \(percentage)%")
    }

    private func unmuteSpeaker() {
        let script = "set volume without output muted"
        runAppleScript(script)
    }

    @discardableResult
    private func runAppleScript(_ script: String) -> String? {
        // Wrap in autoreleasepool to contain NSAppleScript's autoreleased objects
        // and prevent over-release during main run loop drain
        return autoreleasepool {
            var error: NSDictionary?
            guard let scriptObject = NSAppleScript(source: script) else { return nil }
            let result = scriptObject.executeAndReturnError(&error)
            if let error = error {
                print("[Alarm] AppleScript error: \(error)")
                return nil
            }
            // Copy the string value before leaving the autoreleasepool
            return result.stringValue.map { String($0) }
        }
    }

    // MARK: - System Alert Fallback

    private func playSystemAlert() {
        isPlaying = true
        playBeepLoop()
    }

    private func playBeepLoop() {
        guard isPlaying else { return }
        NSSound.beep()
        beepTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            self?.playBeepLoop()
        }
    }

    deinit {
        stopAlarm()
    }
}
