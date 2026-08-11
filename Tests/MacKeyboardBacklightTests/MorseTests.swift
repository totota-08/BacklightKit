import XCTest
@testable import MacKeyboardBacklight

// The private-API layer can't run in CI, but the pure logic (Morse encoding/timing)
// is fully testable. This is where the "abstract the selector layer for tests" point pays off.
final class MorseTests: XCTestCase {

    func testEncodesDotsAndDashes() {
        // E = dot, T = dash, with a 3-unit letter gap between them.
        let (pulses, skipped) = Morse.pulses(for: "ET")
        XCTAssertTrue(skipped.isEmpty)
        XCTAssertEqual(pulses, [.on(units: 1), .off(units: 3), .on(units: 3)])
    }

    func testSymbolGapsWithinLetter() {
        // A = ".-" → dot, 1-unit symbol gap, dash.
        let (pulses, _) = Morse.pulses(for: "A")
        XCTAssertEqual(pulses, [.on(units: 1), .off(units: 1), .on(units: 3)])
    }

    func testWordGapIsSevenUnits() {
        let (pulses, _) = Morse.pulses(for: "E E")
        XCTAssertEqual(pulses, [.on(units: 1), .off(units: 7), .on(units: 1)])
    }

    func testUnknownCharactersAreSkippedNotSwallowed() {
        let (pulses, skipped) = Morse.pulses(for: "E!É")
        XCTAssertEqual(skipped, ["!", "É"])
        XCTAssertEqual(pulses, [.on(units: 1)])   // only E survives
    }

    func testNoTrailingGap() {
        // Playback must not end on an off-pulse (no wasted wait after the last symbol).
        let (pulses, _) = Morse.pulses(for: "SOS")
        XCTAssertTrue(pulses.last?.isOn ?? false)
    }

    func testTrailingAndLeadingSpacesProduceNoEdgeGaps() {
        let (bare, _) = Morse.pulses(for: "SOS")
        for variant in ["SOS ", " SOS", "  SOS  ", "\tSOS\n"] {
            let (p, _) = Morse.pulses(for: variant)
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

    func testDurationMatchesUnitSum() {
        let unit = 0.1
        let (pulses, _) = Morse.pulses(for: "SOS")
        let expected = Double(pulses.reduce(0) { $0 + $1.units }) * unit
        XCTAssertEqual(Morse.duration(for: "SOS", unit: unit), expected, accuracy: 1e-9)
    }
}
