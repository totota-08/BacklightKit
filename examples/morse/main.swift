import Foundation
import MacKeyboardBacklight

// Blink a word in Morse code on the keyboard backlight.
//   swift run example-morse "HELLO WORLD" --unit 0.13 --peak 1.0
//
// Reuses the library: Morse tables/timing from `Morse`, and `withManualControl`
// so the original brightness + auto-brightness are always restored.

func flag(_ name: String, _ args: [String]) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

let args = Array(CommandLine.arguments.dropFirst())
let text = args.first(where: { !$0.hasPrefix("-") }) ?? "SOS"
let unit = Double(flag("--unit", args) ?? "") ?? 0.13
let peak = max(0, min(1, Double(flag("--peak", args) ?? "") ?? 1.0))

guard let kb = KeyboardBacklight() else {
    FileHandle.standardError.write(Data("no keyboard backlight on this Mac\n".utf8)); exit(1)
}

let encoding = Morse.pulses(for: text)
guard !encoding.pulses.isEmpty else {
    FileHandle.standardError.write(Data("nothing to send in \"\(text)\"\n".utf8)); exit(1)
}
if !encoding.skipped.isEmpty { print("skipping unsupported characters: \(String(encoding.skipped))") }
print(String(format: "💡 sending \"%@\" — about %.1fs (unit %.0fms, peak %.0f%%)",
             text, Morse.duration(for: text, unit: unit), unit * 1000, peak * 100))

kb.withManualControl { board in
    for p in encoding.pulses {
        try? board.setBrightness(p.isOn ? peak : 0)
        usleep(useconds_t(unit * Double(p.units) * 1_000_000))
    }
}
print("done — restored")
