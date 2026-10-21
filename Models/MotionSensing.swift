// MotionSensing.swift
// MacGuard - Anti-Theft Alarm for macOS

import Foundation

/// One accelerometer reading in g, parsed from an AppleSPUHIDDevice input report.
struct Acceleration: Equatable {
    let x, y, z: Double

    /// Reports carry three little-endian Int32 axes from byte 6, in 1/65536 g.
    init?(report: UnsafeRawBufferPointer) {
        guard report.count >= 18 else { return nil }
        func axis(_ offset: Int) -> Double {
            Double(Int32(littleEndian: report.loadUnaligned(fromByteOffset: offset, as: Int32.self))) / 65536
        }
        self.init(x: axis(6), y: axis(10), z: axis(14))
    }

    init(x: Double, y: Double, z: Double) {
        self.x = x; self.y = y; self.z = z
    }

    func distance(to other: Acceleration) -> Double {
        ((x - other.x) * (x - other.x) + (y - other.y) * (y - other.y) + (z - other.z) * (z - other.z)).squareRoot()
    }
}

/// Deviation from rest that counts as being moved. A still MacBook measured
/// at most 0.0065 g, so even `.high` leaves a 2x margin.
enum MotionSensitivity: String, CaseIterable, Identifiable {
    case low = "Low", medium = "Medium", high = "High"

    var id: String { rawValue }

    var threshold: Double {
        switch self {
        case .low: return 0.06
        case .medium: return 0.03
        case .high: return 0.015
        }
    }
}

/// Learns the resting gravity vector, then reports once when the low-passed
/// reading leaves it by more than the threshold.
struct MotionDetector {
    static let warmUpSamples = 50
    /// Low-pass weight per sample (~0.1 s at the sensor's 100 Hz)
    static let smoothing = 0.1

    let threshold: Double
    private var warmUp: [Acceleration] = []
    private var rest: Acceleration?
    private var smoothed: Acceleration?
    private var reported = false

    init(sensitivity: MotionSensitivity) {
        threshold = sensitivity.threshold
    }

    /// Returns the deviation (g) the first time it exceeds the threshold.
    mutating func add(_ sample: Acceleration) -> Double? {
        guard let rest else {
            warmUp.append(sample)
            if warmUp.count == Self.warmUpSamples {
                let n = Double(warmUp.count)
                let mean = Acceleration(x: warmUp.map(\.x).reduce(0, +) / n,
                                        y: warmUp.map(\.y).reduce(0, +) / n,
                                        z: warmUp.map(\.z).reduce(0, +) / n)
                rest = mean
                smoothed = mean
            }
            return nil
        }
        let s = smoothed ?? rest
        let a = Self.smoothing
        let next = Acceleration(x: s.x + a * (sample.x - s.x), y: s.y + a * (sample.y - s.y), z: s.z + a * (sample.z - s.z))
        smoothed = next
        let deviation = next.distance(to: rest)
        guard !reported, deviation > threshold else { return nil }
        reported = true
        return deviation
    }
}

/// Lid hinge angle in degrees, from feature report 1 of the lid sensor.
struct LidAngle: Equatable {
    let degrees: Int

    /// Bytes 1-2, little-endian; the angle is the low 9 bits.
    init?(report: [UInt8]) {
        guard report.count >= 3 else { return nil }
        degrees = (Int(report[1]) | Int(report[2]) << 8) & 0x1FF
    }

    init(degrees: Int) {
        self.degrees = degrees
    }
}

/// Reports once when the lid moves `threshold` degrees from where it was armed.
struct LidAngleDetector {
    static let threshold = 5

    private var armedAt: LidAngle?
    private var reported = false

    /// Returns the angle change the first time it reaches the threshold.
    mutating func add(_ angle: LidAngle) -> Int? {
        guard let armedAt else {
            self.armedAt = angle
            return nil
        }
        let change = angle.degrees - armedAt.degrees
        guard !reported, abs(change) >= Self.threshold else { return nil }
        reported = true
        return change
    }
}
