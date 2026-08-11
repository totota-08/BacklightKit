<div align="center">

# kbdlight ⌨️💡

**Read and control the Mac's built-in keyboard backlight — from Swift or the shell.**

[![Platform](https://img.shields.io/badge/platform-macOS%2012%2B-lightgrey.svg)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)
[![SPM](https://img.shields.io/badge/SwiftPM-compatible-brightgreen.svg)](https://swift.org/package-manager/)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

[English](README.md) · [日本語](README.ja.md)

</div>

---

macOS never shipped a public API for the keyboard backlight. `kbdlight` wraps Apple's
**private** `CoreBrightness` framework in a small, well-documented Swift package so you can
read the brightness, set it, watch its real light output in nits, and script light effects —
with **no `sudo`, no entitlements, and no SIP changes**.

Zero dependencies. One binary. Works on Apple Silicon and Intel Macs with a backlit keyboard.

```console
$ kbdlight info
keyboard 95158913 (built-in)
  brightness       : 0.3610  (0.0–1.0)
  light output     : 5.36 nits
  ambient available: true
  auto brightness  : true
  idle dim time    : 0.0 s
```

## Table of contents

- [Install](#install)
- [CLI reference](#cli-reference)
- [Library](#library)
- [Examples](#examples)
- [How it works](#how-it-works)
- [FAQ](#faq)
- [Contributing](#contributing)
- [License](#license)

## Install

**From source (recommended):**

```sh
git clone https://github.com/totota-08/kbdlight
cd kbdlight
make install          # builds -c release and copies the binary to /usr/local/bin
```

Install to a custom prefix with `make install PREFIX=~/.local`.

**Manual build:**

```sh
swift build -c release
cp .build/release/kbdlight /usr/local/bin/
```

## CLI reference

Run `kbdlight help` any time. Every command operates on the built-in keyboard by default.

### `info`
Print the full state of every backlight-capable keyboard.

```sh
kbdlight info            # human-readable
kbdlight info --json     # machine-readable, for scripts
```

| Field | Meaning |
|---|---|
| `brightness` | Current level, `0.0`–`1.0` |
| `light output` | Actual output in **nits** (from Apple's calibration table) |
| `ambient available` | Whether the keyboard has an ambient-light sensor |
| `auto brightness` | Whether auto-brightness is currently on |
| `saturated` / `suppressed` / `dimmed` | Live status flags |
| `idle dim time` | Seconds of inactivity before it dims (`0` = never) |

### `get`
Print just the current brightness as a number — handy in scripts.

```sh
kbdlight get            # -> 0.3610
```

### `set <0..1>`
Set the brightness. Pass `--fade` for a smooth ramp instead of an instant jump.

```sh
kbdlight set 0.5
kbdlight set 1 --fade
```

### `up` / `down` `[step]`
Nudge the brightness up or down. Default step is `0.1`.

```sh
kbdlight up             # +0.10
kbdlight down 0.25      # -0.25
```

### `fade <0..1> [--duration SEC]`
Smoothly ramp from the current level to a target. Default duration `0.6s`.

```sh
kbdlight fade 1.0 --duration 2
```

### `pulse [options]`
"Breathe" the backlight between two levels until you press `Ctrl-C` (which restores the
previous state). Auto-brightness is disabled during the effect so it doesn't fight you.

| Option | Default | Meaning |
|---|---|---|
| `--min <0..1>` | `0.0` | Lower bound |
| `--max <0..1>` | `1.0` | Upper bound |
| `--period <sec>` | `1.6` | Seconds per full breath |
| `--count <n>` | `0` | Number of breaths (`0` = forever) |

```sh
kbdlight pulse --min 0.1 --max 0.8 --period 2
kbdlight pulse --count 3
```

### `auto <on|off>`
Toggle ambient auto-brightness (the sensor-driven behavior).

```sh
kbdlight auto off       # take manual control
kbdlight auto on        # hand it back to the system
```

### `dim <seconds>`
Set the idle-dim timeout. `0` disables idle dimming.

```sh
kbdlight dim 5
kbdlight dim 0
```

## Library

Add the package to your `Package.swift`:

```swift
.package(url: "https://github.com/totota-08/kbdlight", from: "0.1.0")
```

```swift
import MacKeyboardBacklight

guard let kb = KeyboardBacklight() else { return }   // nil on unsupported hardware

print(kb.brightness)              // 0.0 ... 1.0
print(kb.level)                   // physical output in nits (read-only)

kb.brightness = 0.5               // set to 50%
kb.setBrightness(1.0, fade: true) // smooth ramp

kb.autoBrightness = false         // stop the ambient sensor from overriding you
print(kb.isSuppressed, kb.isDimmed, kb.isSaturated)

kb.idleDimTime = 10               // dim after 10s idle

for keyboard in kb.keyboards {    // multiple keyboards are supported
    print(keyboard.id, keyboard.isBuiltIn, kb.brightness(of: keyboard))
}
```

**Public surface:** `keyboards`, `default`, `brightness`, `level` (nits), `autoBrightness`,
`isSaturated`, `isSuppressed`, `isDimmed`, `idleDimTime`, `setBrightness(_:of:fade:)`,
`setAutoBrightness(_:of:)`, `setIdleDimTime(_:of:)`, plus per-keyboard variants of each reader.

## Examples

In [`examples/`](examples):

- **[`TypeGlow.swift`](examples/TypeGlow.swift)** — the backlight flares up on every keystroke
  and fades when you stop. Typing becomes light.
  ```sh
  swift examples/TypeGlow.swift    # type away; 'q' or Ctrl-C to quit
  ```
- **[`KeyboardMorse.playground`](examples/KeyboardMorse.playground)** — blink any word in Morse
  code. Open it in Xcode, change `word`, and run.

## How it works

The built-in keyboard backlight is a single PWM-driven white light guide, exposed in the
IORegistry as an `AppleARMPWMDevice` named `kbd-backlight` (Apple Silicon). Userspace controls
it through the private `KeyboardBrightnessClient` class inside `CoreBrightness.framework`.

`kbdlight` `dlopen`s that framework and calls the class through the Objective-C runtime, so it
links against **nothing private at build time** and fails gracefully — `KeyboardBacklight()`
simply returns `nil` — if Apple ever renames or removes it.

## FAQ

**Can I control individual keys / RGB like a gaming keyboard?**
No. The built-in keyboard is a single white zone with one brightness channel — no per-key
addressing and no color exist in the hardware. That's a physical limitation, not a software one.

**Does it need `sudo` or disabling SIP?**
No. It runs as a normal user with no special entitlements.

**Will an update break it?**
Possibly — it's a private API. Every call is defensive and degrades gracefully, and the code is
tiny enough to fix quickly if a selector changes.

**Is it sandbox-safe?**
No. It relies on a private framework, so it's meant for CLI tools and menu-bar / agent
utilities, not App Store apps.

## Contributing

Issues and PRs welcome. Good first contributions: support for more keyboards, additional
effects in the CLI, and confirming behavior across Mac models and macOS versions (please note
your model and OS build in the PR).

## License

[MIT](LICENSE) © totota-08

> Uses a private Apple framework via runtime lookup. Not affiliated with or endorsed by Apple.
