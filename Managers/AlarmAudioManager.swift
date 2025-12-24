// AlarmAudioManager.swift
// MacGuard - Anti-Theft Alarm for macOS
// Created: 2025-12-18

import AVFoundation
import Cocoa
import CoreAudio

/// Manages alarm audio playback at maximum volume
class AlarmAudioManager: ObservableObject {
    @Published var isPlaying = false

    private var audioPlayer: AVAudioPlayer?
    private var originalVolume: Float = 0.5
    private var originalOutputDeviceID: AudioDeviceID = 0
    private var builtInSpeakerID: AudioDeviceID = 0
    private var shouldRestoreOutputDevice = false
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

        // Switch to built-in speaker (before volume changes)
        switchToBuiltInSpeaker()

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

        // Restore original output device
        restoreOutputDevice()

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

    // MARK: - Audio Output Device Control

    /// Save current output device and switch to built-in speaker
    private func switchToBuiltInSpeaker() {
        // Save current output device
        originalOutputDeviceID = getDefaultOutputDevice()

        // Find built-in speaker
        builtInSpeakerID = findBuiltInSpeaker()

        if builtInSpeakerID != 0 && builtInSpeakerID != originalOutputDeviceID {
            setDefaultOutputDevice(builtInSpeakerID)
            shouldRestoreOutputDevice = true
            print("[Alarm] Switched from device \(originalOutputDeviceID) to built-in speaker \(builtInSpeakerID)")
        } else if builtInSpeakerID == originalOutputDeviceID {
            print("[Alarm] Already using built-in speaker")
            shouldRestoreOutputDevice = false
        } else {
            print("[Alarm] Could not find built-in speaker, using current device")
            shouldRestoreOutputDevice = false
        }
    }

    /// Restore original output device
    private func restoreOutputDevice() {
        guard shouldRestoreOutputDevice, originalOutputDeviceID != 0 else { return }
        setDefaultOutputDevice(originalOutputDeviceID)
        print("[Alarm] Restored output device to \(originalOutputDeviceID)")
        shouldRestoreOutputDevice = false
    }

    /// Get current default output device
    private func getDefaultOutputDevice() -> AudioDeviceID {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )

        if status != noErr {
            print("[Alarm] Failed to get default output device: \(status)")
        }
        return deviceID
    }

    /// Set default output device
    private func setDefaultOutputDevice(_ deviceID: AudioDeviceID) {
        var mutableDeviceID = deviceID
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &mutableDeviceID
        )

        if status != noErr {
            print("[Alarm] Failed to set output device: \(status)")
        }
    }

    /// Find built-in speaker device ID
    private func findBuiltInSpeaker() -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        )

        guard status == noErr else {
            print("[Alarm] Failed to get devices size: \(status)")
            return 0
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &devices
        )

        guard status == noErr else {
            print("[Alarm] Failed to get devices: \(status)")
            return 0
        }

        // Find the built-in output device
        for device in devices {
            if isBuiltInOutputDevice(device) {
                return device
            }
        }

        return 0
    }

    /// Check if device is built-in output speaker
    private func isBuiltInOutputDevice(_ deviceID: AudioDeviceID) -> Bool {
        // Check if device has output streams
        var streamAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var streamSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(deviceID, &streamAddress, 0, nil, &streamSize)
        guard status == noErr && streamSize > 0 else { return false }

        // Check transport type (built-in = kAudioDeviceTransportTypeBuiltIn)
        var transportType: UInt32 = 0
        var transportSize = UInt32(MemoryLayout<UInt32>.size)
        var transportAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        status = AudioObjectGetPropertyData(deviceID, &transportAddress, 0, nil, &transportSize, &transportType)
        guard status == noErr else { return false }

        let isBuiltIn = transportType == kAudioDeviceTransportTypeBuiltIn
        if isBuiltIn {
            print("[Alarm] Found built-in speaker: device ID \(deviceID)")
        }
        return isBuiltIn
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
