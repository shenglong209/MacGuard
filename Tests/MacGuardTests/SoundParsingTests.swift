// SoundParsingTests.swift
// MacGuard - Anti-Theft Alarm for macOS

import XCTest
@testable import MacGuard

final class SoundParsingTests: XCTestCase {
    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    func testSystemSoundParses() {
        XCTAssertNotNil(PlayableSound(url: URL(fileURLWithPath: "/System/Library/Sounds/Ping.aiff")))
    }

    func testRejectsMissingNonAudioAndEmptyFiles() throws {
        try Data("definitely not audio".utf8).write(to: scratch.appendingPathComponent("not-audio.mp3"))
        try Data().write(to: scratch.appendingPathComponent("empty.aiff"))
        for name in ["gone.mp3", "not-audio.mp3", "empty.aiff"] {
            XCTAssertNil(PlayableSound(url: scratch.appendingPathComponent(name)), name)
        }
    }

    func testPickerOffersCustomAndOnlyPlayableBuiltIns() {
        XCTAssertTrue(AlarmSound.offered.contains(.custom))
        for sound in AlarmSound.offered where sound != .custom {
            XCTAssertNotNil(sound.file, "\(sound)")
        }
    }
}
