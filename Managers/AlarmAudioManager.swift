// AlarmAudioManager.swift
// MacGuard - Anti-Theft Alarm for macOS
// Created: 2025-12-18

import AVFoundation
import Cocoa
import CoreAudio

/// A CoreAudio device. The HAL's "unknown" id (0) never becomes one.
struct AudioDevice: Equatable, CustomStringConvertible {
    let id: AudioDeviceID

    init?(_ id: AudioDeviceID) {
        guard id != kAudioObjectUnknown else { return nil }
        self.id = id
    }

    var description: String { "\(id)" }

    private static let system = AudioObjectID(kAudioObjectSystemObject)

    static var defaultOutput: AudioDevice? {
        get { get(system, address(kAudioHardwarePropertyDefaultOutputDevice), as: AudioDeviceID(0)).flatMap(AudioDevice.init) }
        set {
            guard let newValue, !set(system, address(kAudioHardwarePropertyDefaultOutputDevice), newValue.id) else { return }
            logActivity(.alarm, "Failed to set output device \(newValue)")
        }
    }

    static var all: [AudioDevice] {
        var address = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap(AudioDevice.init)
    }

    var isBuiltInOutput: Bool {
        var streams = Self.address(kAudioDevicePropertyStreams, kAudioDevicePropertyScopeOutput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &size) == noErr, size > 0 else { return false }
        return Self.get(id, Self.address(kAudioDevicePropertyTransportType), as: UInt32(0)) == kAudioDeviceTransportTypeBuiltIn
    }

    /// Average output volume (0...1), or nil if the device exposes none.
    var volume: Float? {
        let values = outputElements(kAudioDevicePropertyVolumeScalar).compactMap {
            Self.get(id, Self.output(kAudioDevicePropertyVolumeScalar, $0), as: Float32(0))
        }
        return values.isEmpty ? nil : values.reduce(0, +) / Float(values.count)
    }

    var isMuted: Bool? {
        let values = outputElements(kAudioDevicePropertyMute).compactMap { Self.get(id, Self.output(kAudioDevicePropertyMute, $0), as: UInt32(0)) }
        return values.isEmpty ? nil : values.contains { $0 != 0 }
    }

    func setVolume(_ volume: Float) {
        for element in outputElements(kAudioDevicePropertyVolumeScalar) {
            Self.set(id, Self.output(kAudioDevicePropertyVolumeScalar, element), Float32(min(max(volume, 0), 1)))
        }
    }

    func unmute() {
        for element in outputElements(kAudioDevicePropertyMute) {
            Self.set(id, Self.output(kAudioDevicePropertyMute, element), UInt32(0))
        }
    }

    /// Volume and mute listener addresses on this device.
    var enforcementAddresses: [AudioObjectPropertyAddress] {
        [kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute].flatMap { selector in
            outputElements(selector).map { Self.output(selector, $0) }
        }
    }

    /// Many devices only expose per-channel (1, 2) volume, not the main element.
    private func outputElements(_ selector: AudioObjectPropertySelector) -> [AudioObjectPropertyElement] {
        func has(_ element: AudioObjectPropertyElement) -> Bool {
            var address = Self.output(selector, element)
            return AudioObjectHasProperty(id, &address)
        }
        return has(kAudioObjectPropertyElementMain) ? [kAudioObjectPropertyElementMain] : [1, 2].filter(has)
    }

    static func address(_ selector: AudioObjectPropertySelector,
                        _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func output(_ selector: AudioObjectPropertySelector, _ element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
    }

    private static func get<T: BitwiseCopyable>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, as initial: T) -> T? {
        var address = address
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    @discardableResult
    private static func set<T: BitwiseCopyable>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, _ value: T) -> Bool {
        var address = address
        var value = value
        return AudioObjectSetPropertyData(object, &address, 0, nil, UInt32(MemoryLayout<T>.size), &value) == noErr
    }
}

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

    // MARK: - Logging Helper

    private func log(_ category: ActivityLogCategory, _ message: String) {
        Task { @MainActor in
            ActivityLogManager.shared.log(category, message)
        }
    }

    // MARK: - Preparation

    /// Pre-load audio file so it's ready for instant playback
    func prepare() {
        guard !isPrepared else { return }

        let settings = AppSettings.shared
        if let file = settings.alarmSoundFile {
            do {
                audioPlayer = try AVAudioPlayer(contentsOf: file.url)
                audioPlayer?.numberOfLoops = -1
                audioPlayer?.volume = 1.0
                audioPlayer?.prepareToPlay()
                isPrepared = true
                log(.alarm, "Audio pre-loaded and ready")
            } catch {
                log(.alarm, "Failed to pre-load audio: \(error)")
            }
        }
    }

    /// Release pre-loaded audio
    func unprepare() {
        if !isPlaying {
            audioPlayer?.stop()
            audioPlayer = nil
            isPrepared = false
            log(.alarm, "Audio released")
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
            log(.alarm, "Playing alarm sound (pre-loaded)")
        } else if let file = settings.alarmSoundFile {
            playAudioFile(file.url)
        } else {
            // Fallback to system beep
            log(.alarm, "Alarm sound not found, using system beep")
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

        log(.alarm, "Alarm stopped")
    }

    // MARK: - Volume Enforcement

    /// Start timer to continuously enforce volume (prevents muting via keyboard)
    private func startVolumeEnforcement() {
        stopVolumeEnforcement()
        volumeEnforcementTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            self?.enforceVolume()
        }
        log(.alarm, "Volume enforcement started")
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
            log(.alarm, "Mute blocked - volume restored")
        }

        // Check if volume lowered
        let volumeScript = "output volume of (get volume settings)"
        if let result = runAppleScript(volumeScript),
           let currentVolume = Int(result.trimmingCharacters(in: .whitespacesAndNewlines)) {
            let targetPercentage = Int(targetVolume * 100)
            if currentVolume < targetPercentage - 5 {
                setSystemVolume(targetVolume)
                log(.alarm, "Volume restored from \(currentVolume)% to \(targetPercentage)%")
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
            log(.alarm, "Playing alarm sound")
        } catch {
            log(.alarm, "Failed to play alarm: \(error)")
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
            log(.alarm, "Saved original volume: \(originalVolume)")
        }
    }

    private func setSystemVolume(_ volume: Float) {
        let percentage = Int(volume * 100)
        let script = "set volume output volume \(percentage)"
        runAppleScript(script)
        log(.alarm, "Set volume to \(percentage)%")
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
            log(.alarm, "Switched from device \(originalOutputDeviceID) to built-in speaker \(builtInSpeakerID)")
        } else if builtInSpeakerID == originalOutputDeviceID {
            log(.alarm, "Already using built-in speaker")
            shouldRestoreOutputDevice = false
        } else {
            log(.alarm, "Could not find built-in speaker, using current device")
            shouldRestoreOutputDevice = false
        }
    }

    /// Restore original output device
    private func restoreOutputDevice() {
        guard shouldRestoreOutputDevice, originalOutputDeviceID != 0 else { return }
        setDefaultOutputDevice(originalOutputDeviceID)
        log(.alarm, "Restored output device to \(originalOutputDeviceID)")
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
            log(.alarm, "Failed to get default output device: \(status)")
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
            log(.alarm, "Failed to set output device: \(status)")
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
            log(.alarm, "Failed to get devices size: \(status)")
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
            log(.alarm, "Failed to get devices: \(status)")
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
            log(.alarm, "Found built-in speaker: device ID \(deviceID)")
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
                log(.alarm, "AppleScript error: \(error)")
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
