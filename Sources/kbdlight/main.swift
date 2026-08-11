import Foundation
import MacKeyboardBacklight

// Single source of truth for the version. Bumping this on `main` is what drives the
// Release workflow to tag + publish — the git tag is derived from here, never hand-synced.
let version = "0.2.1"

func die(_ msg: String) -> Never {
    FileHandle.standardError.write(Data("kbdlight: \(msg)\n".utf8)); exit(1)
}

func usage() {
    print("""
    kbdlight \(version) — control the Mac's built-in keyboard backlight

    USAGE:
      kbdlight <command> [args] [--keyboard <id>]

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

    GLOBAL:
      --keyboard <id>      Target a specific keyboard (default: built-in). See `info` for ids.

    Notes:
      • Built-in keyboards are a single white zone — no per-key/RGB control exists in hardware.
      • Uses the private CoreBrightness framework. No sudo, no SIP changes.
      • fade/pulse/morse restore the previous state on Ctrl-C (and SIGTERM).
    """)
}

// MARK: - Argument parsing (order-independent flags)

let valueFlags: Set<String> = ["--duration", "--unit", "--peak", "--min", "--max", "--period", "--count", "--keyboard"]

struct Args {
    var positionals: [String] = []
    var flags: Set<String> = []
    var values: [String: String] = [:]
    func value(_ name: String) -> String? { values[name] }
    func has(_ name: String) -> Bool { flags.contains(name) }
    var first: String? { positionals.first }
}

func parse(_ raw: [String]) -> Args {
    var a = Args(); var i = 0
    while i < raw.count {
        let t = raw[i]
        if valueFlags.contains(t), i + 1 < raw.count { a.values[t] = raw[i + 1]; i += 2; continue }
        if t.hasPrefix("-") { a.flags.insert(t); i += 1; continue }
        a.positionals.append(t); i += 1
    }
    return a
}

// MARK: - Setup

guard let kb = KeyboardBacklight() else {
    die("no controllable keyboard backlight found (unsupported Mac or macOS)")
}

let argv = Array(CommandLine.arguments.dropFirst())
let cmd = argv.first ?? "info"
let opts = parse(Array(argv.dropFirst()))

func targetKeyboard() -> Keyboard {
    guard let idStr = opts.value("--keyboard") else { return kb.defaultKeyboard }
    guard let id = UInt64(idStr), let k = kb.keyboards.first(where: { $0.id == id }) else {
        die("no keyboard with id \(idStr) — run `kbdlight info` for ids")
    }
    return k
}
let board = targetKeyboard()

func clamp(_ v: Double) -> Double { max(0, min(1, v)) }
func fmt(_ d: Double?) -> String { d.map { String(format: "%.2f", $0) } ?? "n/a" }

// Restore `board` to a saved state on Ctrl-C / SIGTERM. Sources are retained globally so
// they outlive the setup scope. Used by the long-running commands (fade/pulse/morse).
var signalSources: [DispatchSourceSignal] = []
func restoreOnInterrupt(brightness: Double, auto: Bool) {
    for s in [SIGINT, SIGTERM] {
        signal(s, SIG_IGN)
        let src = DispatchSource.makeSignalSource(signal: s, queue: .global())
        src.setEventHandler {
            try? board.setBrightness(brightness)
            board.setAutoBrightness(auto)
            exit(0)
        }
        src.resume()
        signalSources.append(src)
    }
}

// MARK: - Commands

switch cmd {
case "help", "-h", "--help":
    usage()

case "--version", "-v":
    print(version)

case "get":
    print(String(format: "%.4f", board.brightness))

case "set":
    guard let s = opts.first, let v = Double(s) else { die("usage: kbdlight set <0..1> [--fade]") }
    do { try board.setBrightness(clamp(v), fade: opts.has("--fade") ? .slow : .none) }
    catch { die("\(error)") }

case "up", "down":
    let step = Double(opts.first ?? "") ?? 0.1
    let target = clamp(board.brightness + (cmd == "up" ? step : -step))
    board.brightness = target
    if let e = board.lastSetError { die("\(e)") }
    print(String(format: "%.4f", target))

case "auto":
    switch opts.first {
    case "on":  board.setAutoBrightness(true)
    case "off": board.setAutoBrightness(false)
    default:    die("usage: kbdlight auto <on|off>")
    }

case "dim":
    guard let s = opts.first, let v = Double(s) else { die("usage: kbdlight dim <seconds>") }
    if !board.setIdleDimTime(v) { die("idle-dim not supported on this Mac") }

case "fade":
    guard let s = opts.first, let target = Double(s) else { die("usage: kbdlight fade <0..1> [--duration SEC]") }
    let dur = Double(opts.value("--duration") ?? "") ?? 0.6
    let start = board.brightness
    restoreOnInterrupt(brightness: start, auto: board.autoBrightness)   // Ctrl-C → back to start
    let steps = max(1, Int(dur / 0.016))
    for i in 1...steps {
        board.brightness = clamp(start + (clamp(target) - start) * Double(i) / Double(steps))
        usleep(useconds_t(dur / Double(steps) * 1_000_000))
    }
    // Normal completion leaves the backlight at the target (that's the point of a fade).

case "pulse":
    let lo = clamp(Double(opts.value("--min") ?? "") ?? 0.0)
    let hi = clamp(Double(opts.value("--max") ?? "") ?? 1.0)
    let period = Double(opts.value("--period") ?? "") ?? 1.6
    let count = Int(opts.value("--count") ?? "") ?? 0     // 0 = forever
    let saved = board.brightness
    let savedAuto = board.autoBrightness
    board.setAutoBrightness(false)
    restoreOnInterrupt(brightness: saved, auto: savedAuto)
    let half = max(1, Int(period / 2 / 0.016))
    var cycle = 0
    while count == 0 || cycle < count {
        for i in 0...half { board.brightness = lo + (hi - lo) * Double(i) / Double(half); usleep(16000) }
        for i in 0...half { board.brightness = hi - (hi - lo) * Double(i) / Double(half); usleep(16000) }
        cycle += 1
    }
    board.brightness = saved
    board.setAutoBrightness(savedAuto)

case "morse":
    guard let text = opts.first else { die("usage: kbdlight morse <text> [--unit SEC] [--peak 0..1]") }
    let unit = Double(opts.value("--unit") ?? "") ?? 0.13
    let peak = clamp(Double(opts.value("--peak") ?? "") ?? 1.0)
    let (pulses, skipped) = Morse.pulses(for: text)
    if pulses.isEmpty { die("nothing to send in \"\(text)\"") }
    if !skipped.isEmpty { print("skipping unsupported: \(String(skipped))") }
    print(String(format: "sending \"%@\" — about %.1fs", text, Morse.duration(for: text, unit: unit)))
    let saved = board.brightness
    let savedAuto = board.autoBrightness
    board.setAutoBrightness(false)
    restoreOnInterrupt(brightness: saved, auto: savedAuto)   // Ctrl-C mid-send restores
    for p in pulses {
        try? board.setBrightness(p.isOn ? peak : 0)
        usleep(useconds_t(unit * Double(p.units) * 1_000_000))
    }
    try? board.setBrightness(saved)
    board.setAutoBrightness(savedAuto)

case "info":
    if opts.has("--json") {
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
