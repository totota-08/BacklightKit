import XCTest
@testable import BacklightKit

// The private-API layer can't run in CI, but the pure logic (Morse encoding/timing)
// is fully testable. This is where the "abstract the selector layer for tests" point pays off.
final class MorseTests: XCTestCase {

    func testEncodesDotsAndDashes() {
        // E = dot, T = dash, with a 3-unit letter gap between them.
        let enc = Morse.pulses(for: "ET")
        XCTAssertTrue(enc.skipped.isEmpty)
        XCTAssertEqual(enc.pulses, [.on(units: 1), .off(units: 3), .on(units: 3)])
    }

    func testSymbolGapsWithinLetter() {
        // A = ".-" → dot, 1-unit symbol gap, dash.
        XCTAssertEqual(Morse.pulses(for: "A").pulses, [.on(units: 1), .off(units: 1), .on(units: 3)])
    }

    func testWordGapIsSevenUnits() {
        XCTAssertEqual(Morse.pulses(for: "E E").pulses, [.on(units: 1), .off(units: 7), .on(units: 1)])
    }

    func testUnknownCharactersAreSkippedNotSwallowed() {
        let enc = Morse.pulses(for: "E!É")
        XCTAssertEqual(enc.skipped, ["!", "É"])
        XCTAssertEqual(enc.pulses, [.on(units: 1)])   // only E survives
    }

    func testNoTrailingGap() {
        // Playback must not end on an off-pulse (no wasted wait after the last symbol).
        XCTAssertTrue(Morse.pulses(for: "SOS").pulses.last?.isOn ?? false)
    }

    func testTrailingAndLeadingSpacesProduceNoEdgeGaps() {
        let bare = Morse.pulses(for: "SOS").pulses
        for variant in ["SOS ", " SOS", "  SOS  ", "\tSOS\n"] {
            let p = Morse.pulses(for: variant).pulses
            XCTAssertEqual(p, bare, "‘\(variant)’ should encode identically to ‘SOS’")
            XCTAssertTrue(p.first?.isOn ?? false)
            XCTAssertTrue(p.last?.isOn ?? false)
        }
    }

    func testConsecutiveSpacesAreASingleWordGap() {
        // "A  B" (two spaces) must still be exactly one 7-unit word gap, not 14.
        let single = Morse.pulses(for: "A B").pulses
        let double = Morse.pulses(for: "A  B").pulses
        XCTAssertEqual(single, double)
        XCTAssertEqual(single.filter { $0 == .off(units: 7) }.count, 1)
    }

    func testWhitespaceOnlyInputIsEmpty() {
        XCTAssertTrue(Morse.pulses(for: "   ").pulses.isEmpty)
    }

    func testEncodingIsEquatable() {
        XCTAssertEqual(Morse.pulses(for: "SOS"), Morse.pulses(for: "sos"))
    }

    func testDurationMatchesUnitSum() {
        let unit = 0.1
        let pulses = Morse.pulses(for: "SOS").pulses
        let expected = Double(pulses.reduce(0) { $0 + $1.units }) * unit
        XCTAssertEqual(Morse.duration(for: "SOS", unit: unit), expected, accuracy: 1e-9)
    }
}
