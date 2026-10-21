// InputParsingTests.swift
// MacGuard - Anti-Theft Alarm for macOS

import XCTest
import CoreGraphics
@testable import MacGuard

final class IntrusionInputTests: XCTestCase {
    /// Every event type the monitor listens for, and what it parses to.
    private let expected: [(UInt32, IntrusionInput)] = [
        (CGEventType.keyDown.rawValue, .keyboard),
        (14, .mediaKey),  // NX_SYSDEFINED: no named CGEventType case
        (CGEventType.flagsChanged.rawValue, .modifier),
        (CGEventType.leftMouseDown.rawValue, .click),
        (CGEventType.rightMouseDown.rawValue, .click),
        (CGEventType.otherMouseDown.rawValue, .click),
        (CGEventType.leftMouseDragged.rawValue, .drag),
        (CGEventType.rightMouseDragged.rawValue, .drag),
        (CGEventType.otherMouseDragged.rawValue, .drag),
        (CGEventType.mouseMoved.rawValue, .pointerMove),
        (CGEventType.scrollWheel.rawValue, .scroll),
    ]

    func testParsesEveryMonitoredEventType() throws {
        for (raw, input) in expected {
            let type = try XCTUnwrap(CGEventType(rawValue: raw), "raw \(raw) must be representable")
            XCTAssertEqual(IntrusionInput(type), input, "raw \(raw)")
        }
    }

    func testIgnoresTapControlAndUnmonitoredEvents() {
        for type: CGEventType in [.tapDisabledByTimeout, .tapDisabledByUserInput, .keyUp,
                                  .leftMouseUp, .rightMouseUp, .otherMouseUp, .null] {
            XCTAssertNil(IntrusionInput(type), "raw \(type.rawValue)")
        }
    }

    func testMaskIsExactlyTheEnumsEventTypes() {
        let fromEnum = IntrusionInput.allCases.flatMap(\.eventTypeRawValues)
        XCTAssertEqual(Set(fromEnum).count, fromEnum.count, "each event type parses to one input")
        XCTAssertEqual(Set(fromEnum), Set(expected.map(\.0)))

        let mask = Set(fromEnum).reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1) }
        XCTAssertEqual(IntrusionInput.eventMask, mask)
        XCTAssertEqual(Set(expected.map(\.1)), Set(IntrusionInput.allCases), "every case is reachable")
    }
}

final class PowerSourceTransitionTests: XCTestCase {
    func testReportsOnlyChanges() {
        let cases: [(PowerSource, PowerSource, PowerSource?)] = [
            (.ac, .battery, .battery), (.battery, .ac, .ac), (.battery, .battery, nil), (.ac, .ac, nil),
        ]
        for (from, to, expected) in cases {
            XCTAssertEqual(PowerMonitor.transition(from: from, to: to), expected, "\(from) -> \(to)")
        }
    }
}
