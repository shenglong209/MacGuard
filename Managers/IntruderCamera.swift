// IntruderCamera.swift
// MacGuard - Anti-Theft Alarm for macOS

import AVFoundation
import AppKit
import SwiftUI

enum IntruderPhotoSetting: String, CaseIterable {
    case off
    case onIntrusion

    static let `default` = IntruderPhotoSetting.off
}

enum CameraAccess: Equatable {
    case notDetermined, granted, denied

    init(_ status: AVAuthorizationStatus) {
        switch status {
        case .authorized: self = .granted
        case .notDetermined: self = .notDetermined
        case .denied, .restricted: self = .denied
        @unknown default: self = .denied
        }
    }
}

/// One photo per arm session, at the first intrusion event.
struct IntruderPhotoPolicy: Equatable {
    private(set) var capturedThisSession = false

    mutating func observe(_ event: AlarmEvent) -> Bool {
        switch event {
        case .armed, .disarmed:
            capturedThisSession = false
            return false
        case .countdownStarted, .alarmSounding:
            guard !capturedThisSession else { return false }
            capturedThisSession = true
            return true
        }
    }
}

enum IntruderPhotoFiles {
    static let keep = 50
    static let fileExtension = "jpg"

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        // ISO 8601 without colons (Finder shows ":" as "/"); sorts chronologically
        f.dateFormat = "yyyy-MM-dd'T'HHmmss.SSS'Z'"
        return f
    }()

    static func filename(for date: Date) -> String {
        "\(formatter.string(from: date)).\(fileExtension)"
    }

    /// Oldest first; non-photos are ignored.
    static func toPrune(_ files: [URL], keep: Int = keep) -> [URL] {
        let photos = files
            .filter { $0.pathExtension.lowercased() == fileExtension }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        return Array(photos.dropFirst(keep).reversed())
    }
}

/// Capture runs off the main actor; a failure never affects the alarm.
@MainActor
final class IntruderCamera: ObservableObject {
    static let shared = IntruderCamera()

    @AppStorage("intruderPhotos") var setting: IntruderPhotoSetting = .default
    @Published private(set) var access = CameraAccess(AVCaptureDevice.authorizationStatus(for: .video))

    let directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("MacGuard/Intruders", isDirectory: true)

    private var policy = IntruderPhotoPolicy()
    private var capture: Task<URL?, Never>?

    private init() {}

    /// Asks for camera permission only now, never at launch.
    func setEnabled(_ enabled: Bool) {
        guard enabled else { setting = .off; return }
        refreshAccess()
        switch access {
        case .granted:
            setting = .onIntrusion
        case .denied:
            setting = .off
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    let camera = IntruderCamera.shared
                    camera.refreshAccess()
                    camera.setting = granted ? .onIntrusion : .off
                }
            }
        }
    }

    func refreshAccess() {
        access = CameraAccess(AVCaptureDevice.authorizationStatus(for: .video))
    }

    func attach(to alarmManager: AlarmStateManager) {
        alarmManager.onEvent { [weak self] event in self?.handle(event) }
    }

    /// Waits for an in-flight capture.
    func latestPhotos(for event: AlarmEvent) async -> [URL] {
        switch event {
        case .countdownStarted, .alarmSounding:
            guard let url = await capture?.value else { return [] }
            return [url]
        case .armed, .disarmed:
            return []
        }
    }

    func revealPhotos() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }

    private func handle(_ event: AlarmEvent) {
        if case .armed = event { capture = nil }
        guard policy.observe(event), setting == .onIntrusion else { return }
        refreshAccess()
        guard access == .granted else {
            logActivity(.alarm, "Intruder photo skipped - camera access not granted")
            return
        }
        let directory = directory
        capture = Task.detached(priority: .userInitiated) {
            await Self.takePhoto(into: directory)
        }
    }

    private nonisolated static func takePhoto(into directory: URL) async -> URL? {
        guard let data = await StillCapture().capture() else {
            logActivity(.alarm, "Intruder photo failed - no image from camera")
            return nil
        }
        let fm = FileManager.default
        let url = directory.appendingPathComponent(IntruderPhotoFiles.filename(for: Date()))
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            logActivity(.alarm, "Intruder photo failed to save: \(error.localizedDescription)")
            return nil
        }
        let existing = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for old in IntruderPhotoFiles.toPrune(existing) {
            try? fm.removeItem(at: old)
        }
        logActivity(.alarm, "Intruder photo saved: \(url.lastPathComponent)")
        return url
    }
}

/// One instance per photo. `@unchecked Sendable`: mutable state is only touched on `queue`.
private final class StillCapture: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    /// Lets auto-exposure settle; the first frames of a cold camera are dark.
    private static let warmUp: TimeInterval = 1.0
    private static let timeout: TimeInterval = 10

    private let queue = DispatchQueue(label: "MacGuard.IntruderCamera")
    private var session: AVCaptureSession?
    private var continuation: CheckedContinuation<Data?, Never>?

    func capture() async -> Data? {
        await withCheckedContinuation { continuation in
            queue.async { self.start(continuation) }
        }
    }

    private func start(_ continuation: CheckedContinuation<Data?, Never>) {
        self.continuation = continuation
        let device = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .unspecified
        ).devices.first ?? AVCaptureDevice.default(for: .video)

        guard let device, let input = try? AVCaptureDeviceInput(device: device) else { return finish(nil) }
        let session = AVCaptureSession()
        session.sessionPreset = .photo
        let output = AVCapturePhotoOutput()
        guard session.canAddInput(input), session.canAddOutput(output) else { return finish(nil) }
        session.addInput(input)
        session.addOutput(output)
        session.startRunning()
        self.session = session

        queue.asyncAfter(deadline: .now() + Self.warmUp) {
            guard self.continuation != nil else { return }
            let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            output.capturePhoto(with: settings, delegate: self)
        }
        queue.asyncAfter(deadline: .now() + Self.timeout) { self.finish(nil) }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = error == nil ? photo.fileDataRepresentation() : nil
        queue.async { self.finish(data) }
    }

    /// Resumes exactly once (photo, failure or timeout) and releases the camera.
    private func finish(_ data: Data?) {
        guard let continuation else { return }
        self.continuation = nil
        session?.stopRunning()
        session = nil
        continuation.resume(returning: data)
    }
}
