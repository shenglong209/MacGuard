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
class AlarmAudioManager {
    /// Everything that exists only while the alarm sounds.
    private struct Playing {
        let targetVolume: Float
        let speaker: AudioDevice?
        /// nil when there is nothing to restore (stopAlarm() also runs on every plain disarm)
        var originalVolume: Float?
        /// nil when the alarm didn't move the output
        var deviceToRestore: AudioDevice?
        /// The device whose volume and mute the listeners watch
        var enforced: AudioDevice?
        var listeners: [(object: AudioObjectID, address: AudioObjectPropertyAddress)] = []
    }

    private var playing: Playing?
    private var audioPlayer: AVAudioPlayer?
    private var beepTimer: Timer?
    private lazy var enforcementBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.enforceVolume() }

    // MARK: - Preparation

    /// Pre-load audio file so it's ready for instant playback
    func prepare() {
        guard audioPlayer == nil else { return }
        let settings = AppSettings.shared
        if settings.customSoundUnavailable {
            logActivity(.alarm, "Custom sound '\(settings.customSoundName)' is unavailable - using the default sound")
        }
        audioPlayer = settings.alarmSoundFile.flatMap { makePlayer($0.url) }
        if audioPlayer != nil { logActivity(.alarm, "Audio pre-loaded and ready") }
    }

    /// Release pre-loaded audio
    func unprepare() {
        guard playing == nil else { return }
        audioPlayer?.stop()
        audioPlayer = nil
        logActivity(.alarm, "Audio released")
    }

    // MARK: - Playback

    func playAlarm() {
        guard playing == nil else { return }

        // Built-in speaker before volume changes
        let speaker = AudioDevice.all.first(where: \.isBuiltInOutput)
        var state = Playing(targetVolume: Float(AppSettings.shared.alarmVolume), speaker: speaker)
        if let speaker {
            logActivity(.alarm, "Found built-in speaker: device ID \(speaker)")
            if let previous = moveToSpeaker(&state) {
                logActivity(.alarm, "Switched from device \(previous) to built-in speaker \(speaker)")
            } else {
                logActivity(.alarm, "Already using built-in speaker")
            }
        } else {
            logActivity(.alarm, "Could not find built-in speaker, using current device")
        }

        state.originalVolume = AudioDevice.defaultOutput?.volume
        logActivity(.alarm, "Saved original volume: \(state.originalVolume.map { String($0) } ?? "unknown")")
        playing = state

        setSystemVolume(state.targetVolume)
        AudioDevice.defaultOutput?.unmute()
        startVolumeEnforcement()

        let preloaded = audioPlayer != nil
        if let player = audioPlayer ?? AppSettings.shared.alarmSoundFile.flatMap({ makePlayer($0.url) }) {
            audioPlayer = player
            player.play()
            logActivity(.alarm, preloaded ? "Playing alarm sound (pre-loaded)" : "Playing alarm sound")
        } else {
            logActivity(.alarm, "Alarm sound not found, using system beep")
            playBeepLoop()
        }
    }

    /// Stop the alarm and restore volume
    func stopAlarm() {
        stopVolumeEnforcement()
        audioPlayer?.stop()
        audioPlayer = nil
        beepTimer?.invalidate()
        beepTimer = nil

        if let state = playing {
            playing = nil
            if let volume = state.originalVolume { setSystemVolume(volume) }
            if let device = state.deviceToRestore {
                AudioDevice.defaultOutput = device
                logActivity(.alarm, "Restored output device to \(device)")
            }
        }
        logActivity(.alarm, "Alarm stopped")
    }

    private func makePlayer(_ url: URL) -> AVAudioPlayer? {
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = 1.0
            player.prepareToPlay()
            return player
        } catch {
            logActivity(.alarm, "Failed to load alarm sound: \(error)")
            return nil
        }
    }

    // MARK: - Volume Enforcement

    /// Reacts to output device, volume and mute changes (keys, connecting headphones).
    private func startVolumeEnforcement() {
        stopVolumeEnforcement()
        guard playing != nil else { return }
        let device = AudioDevice.defaultOutput
        let targets = [(AudioObjectID(kAudioObjectSystemObject), AudioDevice.address(kAudioHardwarePropertyDefaultOutputDevice))]
            + (device.map { d in d.enforcementAddresses.map { (d.id, $0) } } ?? [])
        playing?.enforced = device
        for (object, address) in targets {
            var address = address
            if AudioObjectAddPropertyListenerBlock(object, &address, .main, enforcementBlock) == noErr {
                playing?.listeners.append((object, address))
            }
        }
        logActivity(.alarm, "Volume enforcement started")
    }

    private func stopVolumeEnforcement() {
        for (object, address) in playing?.listeners ?? [] {
            var address = address
            AudioObjectRemovePropertyListenerBlock(object, &address, .main, enforcementBlock)
        }
        playing?.listeners = []
    }

    private func enforceVolume() {
        guard var state = playing else { return }

        // Connecting headphones moves the default output, and the alarm with it.
        if let moved = moveToSpeaker(&state) {
            playing = state
            logActivity(.alarm, "Output moved to device \(moved) - alarm kept on built-in speaker")
        }
        // No built-in speaker to return to: follow the new device instead
        if AudioDevice.defaultOutput != state.enforced { startVolumeEnforcement() }

        // A device change can stop the player
        if let player = audioPlayer, !player.isPlaying {
            player.play()
            logActivity(.alarm, "Alarm playback resumed after an output change")
        }

        let output = AudioDevice.defaultOutput
        if output?.isMuted == true {
            output?.unmute()
            setSystemVolume(state.targetVolume)
            logActivity(.alarm, "Mute blocked - volume restored")
        }
        if let current = output?.volume, current < state.targetVolume - 0.05 {
            setSystemVolume(state.targetVolume)
            logActivity(.alarm, "Volume restored from \(Int(current * 100))% to \(Int(state.targetVolume * 100))%")
        }
    }

    // CoreAudio, not AppleScript: enforcement runs on every volume change, on the main thread.
    private func setSystemVolume(_ volume: Float) {
        AudioDevice.defaultOutput?.setVolume(volume)
        logActivity(.alarm, "Set volume to \(Int(min(max(volume, 0), 1) * 100))%")
    }

    /// Returns the device it replaced, which becomes the one restored on stop.
    private func moveToSpeaker(_ state: inout Playing) -> AudioDevice? {
        guard let speaker = state.speaker, let current = AudioDevice.defaultOutput, current != speaker else { return nil }
        state.deviceToRestore = current
        AudioDevice.defaultOutput = speaker
        return current
    }

    // MARK: - System Alert Fallback

    private func playBeepLoop() {
        guard playing != nil else { return }
        NSSound.beep()
        beepTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            self?.playBeepLoop()
        }
    }

    deinit {
        stopAlarm()
    }
}
