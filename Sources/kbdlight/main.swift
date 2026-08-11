import Foundation
import MacKeyboardBacklight

let version = "0.2.0"

func die(_ msg: String) -> Never {
    FileHandle.standardError.write(Data("kbdlight: \(msg)\n".utf8)); exit(1)
}

func usage() {
    print("""
    kbdlight \(version) — control the Mac's built-in keyboard backlight

    USAGE:
      kbdlight <command> [args]

    COMMANDS:
      info                 Show everything about every keyboard (add --json for JSON)
      get                  Print current brightness (0.0 – 1.0)
      set <0..1>           Set brightness. --fade for a smooth ramp
      up [step]            Raise brightness (default step 0.1)
      down [step]          Lower brightness
      fade <0..1>          Ramp to a target over --duration SEC (default 0.6)
      pulse                Breathe between --min and --max. --count N, --period SEC
      morse <text>         Blink text in Morse code. --unit SEC, --peak 0..1
      auto <on|off>        Toggle ambient auto-brightness
      dim <seconds>        Set idle-dim timeout (0 = never)
      help | --version

    Notes:
      • Built-in keyboards are a single white zone — no per-key/RGB control exists in hardware.
      • Uses the private CoreBrightness framework. No sudo, no SIP changes.
    """)
}

guard let kb = KeyboardBacklight() else {
    die("no controllable keyboard backlight found (unsupported Mac or macOS)")
}
let board = kb.defaultKeyboard

func clamp(_ v: Double) -> Double { max(0, min(1, v)) }
func flagValue(_ name: String, _ args: [String]) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}
func fmt(_ d: Double?) -> String { d.map { String(format: "%.2f", $0) } ?? "n/a" }

let args = Array(CommandLine.arguments.dropFirst())
let cmd = args.first ?? "info"
let rest = Array(args.dropFirst())

switch cmd {
case "help", "-h", "--help":
    usage()

case "--version", "-v":
    print(version)

case "get":
    print(String(format: "%.4f", board.brightness))

case "set":
    guard let s = rest.first, let v = Double(s) else { die("usage: kbdlight set <0..1>") }
    do { try board.setBrightness(clamp(v), fade: rest.contains("--fade") ? .slow : .none) }
    catch { die("\(error)") }

case "up", "down":
    let step = Double(rest.first ?? "") ?? 0.1
    let target = clamp(board.brightness + (cmd == "up" ? step : -step))
    board.brightness = target
    if let e = board.lastSetError { die("\(e)") }
    print(String(format: "%.4f", target))

case "auto":
    switch rest.first {
    case "on":  board.setAutoBrightness(true)
    case "off": board.setAutoBrightness(false)
    default:    die("usage: kbdlight auto <on|off>")
    }

case "dim":
    guard let s = rest.first, let v = Double(s) else { die("usage: kbdlight dim <seconds>") }
    if !board.setIdleDimTime(v) { die("idle-dim not supported on this Mac") }

case "fade":
    guard let s = rest.first, let target = Double(s) else { die("usage: kbdlight fade <0..1>") }
    let dur = Double(flagValue("--duration", rest) ?? "") ?? 0.6
    let start = board.brightness
    let steps = max(1, Int(dur / 0.016))
    for i in 1...steps {
        board.brightness = clamp(start + (clamp(target) - start) * Double(i) / Double(steps))
        usleep(useconds_t(dur / Double(steps) * 1_000_000))
    }

case "pulse":
    let lo = clamp(Double(flagValue("--min", rest) ?? "") ?? 0.0)
    let hi = clamp(Double(flagValue("--max", rest) ?? "") ?? 1.0)
    let period = Double(flagValue("--period", rest) ?? "") ?? 1.6
    let count = Int(flagValue("--count", rest) ?? "") ?? 0     // 0 = forever
    let saved = board.brightness
    let savedAuto = board.autoBrightness
    board.setAutoBrightness(false)
    // Restore cleanly on Ctrl-C via a GCD signal source (captures context, unlike signal()).
    var stop = false
    signal(SIGINT, SIG_IGN)
    let sig = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
    sig.setEventHandler {
        board.brightness = saved; board.setAutoBrightness(savedAuto); exit(0)
    }
    sig.resume()
    let half = max(1, Int(period / 2 / 0.016))
    var cycle = 0
    while (count == 0 || cycle < count) && !stop {
        for i in 0...half { board.brightness = lo + (hi - lo) * Double(i) / Double(half); usleep(16000) }
        for i in 0...half { board.brightness = hi - (hi - lo) * Double(i) / Double(half); usleep(16000) }
        cycle += 1
    }
    board.brightness = saved
    board.setAutoBrightness(savedAuto)

case "morse":
    guard let text = rest.first(where: { !$0.hasPrefix("-") }) else { die("usage: kbdlight morse <text>") }
    let unit = Double(flagValue("--unit", rest) ?? "") ?? 0.13
    let peak = clamp(Double(flagValue("--peak", rest) ?? "") ?? 1.0)
    let (pulses, skipped) = Morse.pulses(for: text)
    if pulses.isEmpty { die("nothing to send in \"\(text)\"") }
    if !skipped.isEmpty { print("skipping unsupported: \(String(skipped))") }
    print(String(format: "sending \"%@\" — about %.1fs", text, Morse.duration(for: text, unit: unit)))
    board.withManualControl { b in
        for p in pulses {
            try? b.setBrightness(p.isOn ? peak : 0)
            usleep(useconds_t(unit * Double(p.units) * 1_000_000))
        }
    }

case "info":
    if rest.contains("--json") {
        var items: [String] = []
        for k in kb.keyboards {
            let nits: String = k.nits.map { String($0) } ?? "null"
            items.append("{\"id\":\(k.id),\"builtIn\":\(k.isBuiltIn),\"ambient\":\(k.supportsAmbient),\"brightness\":\(k.brightness),\"nits\":\(nits)}")
        }
        print("[\(items.joined(separator: ","))]")
    } else {
        for k in kb.keyboards {
            print("keyboard \(k.id)\(k.isBuiltIn ? " (built-in)" : "")")
            print(String(format: "  brightness       : %.4f  (0.0–1.0)", k.brightness))
            print("  light output     : \(k.nits.map { String(format: "%.2f nits", $0) } ?? "n/a")")
            print("  ambient available: \(k.supportsAmbient)")
            print("  auto brightness  : \(k.autoBrightness)")
            print("  saturated        : \(k.isSaturated.map(String.init) ?? "n/a")")
            print("  suppressed       : \(k.isSuppressed.map(String.init) ?? "n/a")")
            print("  dimmed (idle)    : \(k.isDimmed.map(String.init) ?? "n/a")")
            print("  idle dim time    : \(fmt(k.idleDimTime)) s")
        }
    }

default:
    die("unknown command '\(cmd)' — try 'kbdlight help'")
}
