# kbdlight ⌨️💡

**A clean Swift API + CLI for the Mac's built-in keyboard backlight.**

macOS never gave apps a public way to read or set the keyboard backlight. This wraps
Apple's *private* `CoreBrightness` framework in a small, well-documented library so you
can control it from Swift — or from the shell — with **no `sudo`, no entitlements, and
no SIP changes**.

Zero dependencies. Single binary. Apple Silicon & Intel Macs with a backlit keyboard.

```
$ kbdlight info
keyboard 95158913 (built-in)
  brightness       : 0.3610  (0.0–1.0)
  light output     : 5.36 nits
  ambient available: true
  auto brightness  : true
  idle dim time    : 0.0 s
```

## Install

```sh
git clone https://github.com/totota-08/kbdlight
cd kbdlight
make install        # builds release and copies kbdlight to /usr/local/bin
```

Or just `swift build -c release` and grab `.build/release/kbdlight`.

## CLI

| Command | What it does |
|---|---|
| `kbdlight info [--json]` | Dump every keyboard's state |
| `kbdlight get` | Print brightness (0.0–1.0) |
| `kbdlight set <0..1> [--fade]` | Set brightness |
| `kbdlight up [step]` / `down [step]` | Nudge brightness (default step 0.1) |
| `kbdlight fade <0..1> [--duration SEC]` | Smooth ramp to a target |
| `kbdlight pulse [--min --max --count --period]` | Breathing effect (Ctrl-C safe) |
| `kbdlight auto <on\|off>` | Toggle ambient auto-brightness |
| `kbdlight dim <seconds>` | Idle-dim timeout (0 = never) |

## Library

Add to `Package.swift`:

```swift
.package(url: "https://github.com/totota-08/kbdlight", from: "0.1.0")
```

```swift
import MacKeyboardBacklight

guard let kb = KeyboardBacklight() else { return }   // nil on unsupported hardware

print(kb.brightness)          // 0.0 ... 1.0
print(kb.level)               // physical output in nits
kb.brightness = 0.5           // set to 50%
kb.setBrightness(1.0, fade: true)

kb.autoBrightness = false     // stop the ambient sensor from overriding you
print(kb.isSuppressed, kb.isDimmed)

for k in kb.keyboards {        // multiple keyboards supported
    print(k.id, k.isBuiltIn, kb.brightness(of: k))
}
```

Full surface: `brightness`, `level` (nits), `autoBrightness`, `isSaturated`,
`isSuppressed`, `isDimmed`, `idleDimTime`, `setBrightness(_:fade:)`, and per-keyboard
variants of each.

## How it works

The built-in keyboard backlight is a single PWM-driven white light guide — exposed in the
IORegistry as an `AppleARMPWMDevice` named `kbd-backlight`. Userspace controls it through
the private `KeyboardBrightnessClient` class in `CoreBrightness.framework`. This library
`dlopen`s that framework and calls the class via the Objective-C runtime, so it links
against nothing private at build time and fails gracefully (returns `nil`) if Apple ever
changes it.

**No per-key / RGB control exists.** The hardware has one zone and one channel (brightness
only, no color) — that's a physical limitation, not a software one.

## Caveats

- Private API: could break on any macOS update. Every call is defensive.
- Not sandbox-safe; intended for CLI tools and menu-bar/agent utilities.
- Setting brightness while auto-brightness is on can fight the ambient sensor — turn it off
  first (`kbdlight auto off`) for steady effects.

## License

MIT © totota-08
