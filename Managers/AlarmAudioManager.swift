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

    // MARK: - Playback

    /// Play the alarm sound at maximum volume
    func playAlarm() {
        guard !isPlaying else { return }

        // Save original volume
        saveOriginalVolume()

        // Set system volume to max
        setSystemVolume(1.0)

        // Unmute if muted
        unmuteSpeaker()

        // Try to load alarm sound from module bundle (SPM resources)
        let bundle = Bundle.module
        if let url = bundle.url(forResource: "alarm", withExtension: "mp3", subdirectory: "Resources")
            ?? bundle.url(forResource: "alarm", withExtension: "aiff", subdirectory: "Resources")
            ?? bundle.url(forResource: "alarm", withExtension: "wav", subdirectory: "Resources") {
            playAudioFile(url)
        } else if FileManager.default.fileExists(atPath: "/System/Library/Sounds/Funk.aiff") {
            // Use system Funk sound as fallback
            playAudioFile(URL(fileURLWithPath: "/System/Library/Sounds/Funk.aiff"))
        } else {
            // Fallback to system beep
            print("[Alarm] Alarm sound not found, using system beep")
            playSystemAlert()
        }
    }

    /// Stop the alarm and restore volume
    func stopAlarm() {
        audioPlayer?.stop()
        audioPlayer = nil
        beepTimer?.invalidate()
        beepTimer = nil
        isPlaying = false

        // Restore original volume
        setSystemVolume(originalVolume)

        print("[Alarm] Alarm stopped")
    }

    // MARK: - Audio File Playback

    private func playAudioFile(_ url: URL) {
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.numberOfLoops = -1 // Loop forever
            audioPlayer?.volume = 1.0
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
