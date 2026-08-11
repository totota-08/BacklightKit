import Foundation

/// International Morse code, plus the timing needed to "play" it on a light.
///
/// Timing follows ITU-R M.1677, measured in *units* (one unit = one dot):
/// - dot = **1** on, dash = **3** on
/// - gap between symbols in a letter = **1** off
/// - gap between letters = **3** off
/// - gap between words = **7** off
public enum Morse {

    public static let table: [Character: String] = [
        "A": ".-", "B": "-...", "C": "-.-.", "D": "-..", "E": ".", "F": "..-.",
        "G": "--.", "H": "....", "I": "..", "J": ".---", "K": "-.-", "L": ".-..",
        "M": "--", "N": "-.", "O": "---", "P": ".--.", "Q": "--.-", "R": ".-.",
        "S": "...", "T": "-", "U": "..-", "V": "...-", "W": ".--", "X": "-..-",
        "Y": "-.--", "Z": "--..", "0": "-----", "1": ".----", "2": "..---",
        "3": "...--", "4": "....-", "5": ".....", "6": "-....", "7": "--...",
        "8": "---..", "9": "----.",
    ]

    /// One step of a Morse playback: light `on` for N units, or `off` (gap) for N units.
    public enum Pulse: Equatable, Sendable {
        case on(units: Int)
        case off(units: Int)
        public var units: Int { switch self { case .on(let u), .off(let u): return u } }
        public var isOn: Bool { if case .on = self { return true } else { return false } }
    }

    /// Turn text into a flat pulse list with all gaps made explicit, plus the set of
    /// characters that had no Morse mapping (skipped rather than silently swallowed).
    public static func pulses(for text: String) -> (pulses: [Pulse], skipped: [Character]) {
        var out: [Pulse] = []
        var skipped: [Character] = []
        let letters = Array(text.uppercased())

        var firstLetterEmitted = false
        for ch in letters {
            if ch == " " {
                if !out.isEmpty { out.append(.off(units: 7)) }   // word gap
                firstLetterEmitted = false
                continue
            }
            guard let code = table[ch] else { skipped.append(ch); continue }
            if firstLetterEmitted { out.append(.off(units: 3)) } // letter gap
            firstLetterEmitted = true
            for (i, symbol) in code.enumerated() {
                if i > 0 { out.append(.off(units: 1)) }          // symbol gap
                out.append(.on(units: symbol == "-" ? 3 : 1))    // dash / dot
            }
        }
        return (out, skipped)
    }

    /// Total playback time for `text` at a given unit length (seconds).
    public static func duration(for text: String, unit: Double) -> Double {
        Double(pulses(for: text).pulses.reduce(0) { $0 + $1.units }) * unit
    }
}
