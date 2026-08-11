import Foundation
import MacKeyboardBacklight

let version = "0.1.0"

func die(_ msg: String) -> Never {
    FileHandle.standardError.write(Data("kbdlight: \(msg)\n".utf8))
    exit(1)
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
      pulse                Breathe between --min and --max. --count N, --period SEC
      fade <0..1>          Ramp to a target over --duration SEC (default 0.6)
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

func clamp(_ v: Float) -> Float { max(0, min(1, v)) }

func flagValue(_ name: String, _ args: [String]) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

let args = Array(CommandLine.arguments.dropFirst())
let cmd = args.first ?? "info"
let rest = Array(args.dropFirst())

switch cmd {
case "help", "-h", "--help":
    usage()

case "--version", "-v":
    print(version)

case "get":
    print(String(format: "%.4f", kb.brightness))

case "set":
    guard let s = rest.first, let v = Float(s) else { die("usage: kbdlight set <0..1>") }
    kb.setBrightness(clamp(v), fade: rest.contains("--fade"))

case "up", "down":
    let step = Float(rest.first ?? "") ?? 0.1
    let delta = cmd == "up" ? step : -step
    let target = clamp(kb.brightness + delta)
    kb.setBrightness(target)
    print(String(format: "%.4f", target))

case "auto":
    switch rest.first {
    case "on":  kb.setAutoBrightness(true)
    case "off": kb.setAutoBrightness(false)
    default:    die("usage: kbdlight auto <on|off>")
    }

case "dim":
    guard let s = rest.first, let v = Double(s) else { die("usage: kbdlight dim <seconds>") }
    kb.setIdleDimTime(v)

case "fade":
    guard let s = rest.first, let target = Float(s) else { die("usage: kbdlight fade <0..1>") }
    let dur = Double(flagValue("--duration", rest) ?? "") ?? 0.6
    let start = kb.brightness
    let steps = max(1, Int(dur / 0.016))
    for i in 1...steps {
        let t = Float(i) / Float(steps)
        kb.setBrightness(clamp(start + (clamp(target) - start) * t))
        usleep(useconds_t(dur / Double(steps) * 1_000_000))
    }

case "pulse":
    let lo = clamp(Float(flagValue("--min", rest) ?? "") ?? 0.0)
    let hi = clamp(Float(flagValue("--max", rest) ?? "") ?? 1.0)
    let period = Double(flagValue("--period", rest) ?? "") ?? 1.6
    let count = Int(flagValue("--count", rest) ?? "") ?? 0   // 0 = forever
    let saved = kb.brightness
    let savedAuto = kb.autoBrightness
    kb.setAutoBrightness(false)
    // restore on Ctrl-C
    signal(SIGINT) { _ in
        if let k = KeyboardBacklight() { k.setBrightness(0.0); k.setAutoBrightness(true) }
        exit(0)
    }
    let half = max(1, Int(period / 2 / 0.016))
    var cycle = 0
    while count == 0 || cycle < count {
        for i in 0...half { kb.setBrightness(lo + (hi - lo) * Float(i) / Float(half)); usleep(16000) }
        for i in 0...half { kb.setBrightness(hi - (hi - lo) * Float(i) / Float(half)); usleep(16000) }
        cycle += 1
    }
    kb.setBrightness(saved)
    kb.setAutoBrightness(savedAuto)

case "info":
    let json = rest.contains("--json")
    if json {
        var arr: [String] = []
        for k in kb.keyboards {
            arr.append("""
              {"id":\(k.id),"builtIn":\(k.isBuiltIn),"ambientAvailable":\(k.ambientFeatureAvailable),\
            "brightness":\(kb.brightness(of: k)),"nits":\(kb.level(of: k))}
            """)
        }
        print("[\(arr.joined(separator: ","))]")
    } else {
        for k in kb.keyboards {
            print("keyboard \(k.id)\(k.isBuiltIn ? " (built-in)" : "")")
            print(String(format: "  brightness       : %.4f  (0.0–1.0)", kb.brightness(of: k)))
            print(String(format: "  light output     : %.2f nits", kb.level(of: k)))
            print("  ambient available: \(k.ambientFeatureAvailable)")
            if k.id == kb.default.id {
                print("  auto brightness  : \(kb.autoBrightness)")
                print("  saturated        : \(kb.isSaturated)")
                print("  suppressed       : \(kb.isSuppressed)")
                print("  dimmed (idle)    : \(kb.isDimmed)")
                print(String(format: "  idle dim time    : %.1f s", kb.idleDimTime))
            }
        }
    }

default:
    die("unknown command '\(cmd)' — try 'kbdlight help'")
}
