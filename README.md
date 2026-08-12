<div align="center">

# BacklightKit ⌨️💡

**Read and control the Mac's built-in keyboard backlight — from Swift (`BacklightKit`) or the shell (`backlit`).**

[![CI](https://github.com/totota-08/BacklightKit/actions/workflows/ci.yml/badge.svg)](https://github.com/totota-08/BacklightKit/actions/workflows/ci.yml)
[![Release](https://github.com/totota-08/BacklightKit/actions/workflows/release.yml/badge.svg)](https://github.com/totota-08/BacklightKit/actions/workflows/release.yml)
[![Platform](https://img.shields.io/badge/platform-macOS%2012%2B-lightgrey.svg)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

[English](README.md) · [日本語](README.ja.md)

</div>

---

macOS never shipped a public API for the keyboard backlight. **BacklightKit** wraps Apple's
**private** `CoreBrightness` framework in a small, well-documented Swift package so you can
read the brightness, set it, watch its real light output in nits, and script light effects —
with **no `sudo`, no entitlements, and no SIP changes**.

Zero dependencies. One binary. **macOS only** — see [Platform & verification](#platform--verification)
(tested on Apple Silicon M1; other Macs are unverified since I don't own them).

```console
$ backlit info
keyboard 95158913 (built-in)
  brightness       : 0.3610  (0.0–1.0)
  light output     : 5.36 nits
  auto supported   : true
  auto brightness  : true
  saturated        : false
  suppressed       : false
  dimmed (idle)    : false
  idle dim time    : 0.00 s
```

> ⚠️ **Private API.** This calls an undocumented Apple framework through the Objective-C
> runtime. It needs no special privileges and fails gracefully, but Apple could change or
> remove it in any macOS update. See [How it works](#how-it-works) and [verified builds](#verified-on).

## Table of contents

- [Install](#install)
- [CLI reference](#cli-reference)
- [Library](#library)
- [Examples](#examples)
- [How it works](#how-it-works)
- [Platform & verification](#platform--verification)
- [FAQ](#faq)
- [Contributing](#contributing)
- [License](#license)

## Install

### Homebrew

```sh
brew install totota-08/tap/backlit
```

### Swift Package Manager (library)

```swift
dependencies: [
    .package(url: "https://github.com/totota-08/BacklightKit", from: "0.3.0")
]
```
```swift
.target(name: "YourApp", dependencies: [
    .product(name: "BacklightKit", package: "BacklightKit")
])
```

### From source

```sh
git clone https://github.com/totota-08/BacklightKit
cd BacklightKit
make install          # builds -c release, copies the binary to /usr/local/bin
```

Prebuilt binaries are attached to every [release](https://github.com/totota-08/BacklightKit/releases).

## CLI reference

Run `backlit help` any time. Every command targets the built-in keyboard by default; add
`--keyboard <id>` (ids come from `backlit info`) to target another one. `fade`, `pulse`, and
`morse` restore the previous state on `Ctrl-C` / `SIGTERM`.

### `info`
Print the full state of every backlight-capable keyboard.

```sh
backlit info            # human-readable
backlit info --json     # machine-readable
```

| Field | Meaning |
|---|---|
| `brightness` | Current level, `0.0`–`1.0` |
| `light output` | Actual output in **nits** (Apple's calibration table), or `n/a` |
| `auto supported` | Whether the keyboard has an ambient-light sensor |
| `auto brightness` | Whether auto-brightness is on |
| `saturated` / `suppressed` / `dimmed` | Live status flags (`n/a` if unsupported) |
| `idle dim time` | Seconds idle before dimming (`0` = never) |

### `get`
Print just the current brightness — handy in scripts.

```sh
backlit get            # -> 0.3610
```

### `set <0..1>`
Set the brightness. `--fade` asks the system for a smooth ramp instead of an instant jump.

```sh
backlit set 0.5
backlit set 1 --fade
```

### `up` / `down` `[step]`
Nudge brightness up/down. Default step `0.1`.

```sh
backlit up             # +0.10
backlit down 0.25      # -0.25
```

### `fade <0..1> [--duration SEC]`
Smoothly ramp from the current level to a target. Default duration `0.6s`.

```sh
backlit fade 1.0 --duration 2
```

### `pulse [options]`
"Breathe" between two levels until `Ctrl-C` (which restores the previous state). Auto-brightness
is disabled during the effect so the sensor won't fight it.

| Option | Default | Meaning |
|---|---|---|
| `--min <0..1>` | `0.0` | Lower bound |
| `--max <0..1>` | `1.0` | Upper bound |
| `--period <sec>` | `1.6` | Seconds per full breath |
| `--count <n>` | `0` | Number of breaths (`0` = forever) |

```sh
backlit pulse --min 0.1 --max 0.8 --period 2
backlit pulse --count 3
```

### `morse <text> [options]`
Blink text in Morse code. Prints the total time up front, skips unsupported characters, and
restores the previous state when done.

| Option | Default | Meaning |
|---|---|---|
| `--unit <sec>` | `0.13` | Length of one Morse unit (a dot) |
| `--peak <0..1>` | `1.0` | Brightness of the "on" flashes |

```sh
backlit morse SOS
backlit morse "hello world" --unit 0.08 --peak 0.7
```

### `auto <on|off>`
Toggle ambient auto-brightness.

```sh
backlit auto off       # manual control
backlit auto on        # hand it back to the system
```

### `dim <seconds>`
Set the idle-dim timeout. `0` disables idle dimming.

```sh
backlit dim 5
backlit dim 0
```

### `flash [options]`
Blink the backlight a few times as a **notification**, then restore. Handy to wire to a
task-completion hook ("build done", "tests passed").

| Option | Default | Meaning |
|---|---|---|
| `--count <n>` | `3` | Number of blinks |
| `--peak <0..1>` | `1.0` | Brightness of each blink |
| `--on <sec>` | `0.12` | On duration per blink |
| `--off <sec>` | `0.12` | Off gap between blinks |

```sh
backlit flash                       # 3 quick blinks, then back to where it was
make build && backlit flash         # blink when the build finishes
backlit flash --count 5 --peak 0.7  # gentler, five times
```

> Wire it to a completion hook — e.g. a Claude Code **Stop** hook that runs `backlit flash`
> so the keyboard blinks whenever a task finishes.

### `hold <command...>`
Run a command with idle dimming **suspended**, then restore the previous state — without
touching your configured `dim` timeout. Useful for keeping the keyboard lit through a task.

```sh
backlit hold sleep 300         # stay lit for 5 minutes, then restore
backlit hold ./run-demo.sh     # lit for the demo's duration
```

### `watch`
Print the brightness on every change. **Event-driven** where the OS supports it (the system
pushes each change — no polling, no latency), falling back to polling otherwise. `Ctrl-C` to stop.

```sh
backlit watch                  # 0.5000, then a line per change
```

## Library

The subject you operate on is a `Keyboard`. `KeyboardBacklight()` discovers them and forwards
convenience accessors to the default (built-in) one.

```swift
import BacklightKit

guard let kb = KeyboardBacklight() else { return }   // nil on unsupported hardware
// …or, when you need to know WHY it failed:
// let kb = try KeyboardBacklight.discover()         // throws a DiscoveryError

// Subject-first: operate on a keyboard directly.
kb.builtIn?.brightness = 1.0
print(kb.defaultKeyboard.nits ?? -1)                 // physical output in nits (Double?)

// Convenience: every Keyboard property is forwarded to the default keyboard
// (dynamic member lookup), so this just works:
kb.brightness = 0.5
print(kb.brightness)

// One error story: every write has a throwing method. The property setters are
// fire-and-forget conveniences that ignore failure.
try kb.setBrightness(1.0, fade: .slow)               // FadeSpeed: .instant / .slow / .fast
try kb.setAutoBrightness(false)
try kb.setIdleDimTime(30)

// Scoped manual control: saves brightness + auto, disables auto, ALWAYS restores.
try kb.withManualControl { board in
    for _ in 0..<3 {
        try board.setBrightness(1); usleep(120_000)
        try board.setBrightness(0); usleep(120_000)
    }
}

// The async variant lets you use Task.sleep instead of blocking a thread.
try await kb.withManualControl { board in
    try board.setBrightness(1)
    try await Task.sleep(nanoseconds: 120_000_000)
    try board.setBrightness(0)
}

// "Unsupported" is nil, never a fake 0.
print(kb.isSuppressed ?? false, kb.defaultKeyboard.idleDimTime ?? 0)

// Watch changes via an AsyncStream. Event-driven where the OS supports it (the system
// pushes each change — no polling), falling back to polling otherwise.
Task {
    for await level in kb.defaultKeyboard.brightnessStream() {
        print("brightness →", level)
    }
}

// Keep the keyboard lit through a task without changing the configured dim timeout;
// the previous suspend state is always restored, even if the body throws.
try kb.withIdleDimmingSuspended {
    runLongPresentation()
}

// Every keyboard, not just the default. Keyboard is Identifiable + Hashable,
// so kb.keyboards drops straight into SwiftUI's ForEach.
for keyboard in kb.keyboards {
    print(keyboard.id, keyboard.isBuiltIn, keyboard.brightness)
}
```

**`Keyboard`** — `brightness` (get/set, `Double`), `setBrightness(_:fade:) throws`,
`nits: Double?`, `autoBrightness`, `setAutoBrightness(_:) throws`, `supportsAutoBrightness`,
`isSaturated/isSuppressed/isDimmed: Bool?`, `idleDimTime: TimeInterval?` (read-only),
`setIdleDimTime(_:) throws`, `disableIdleDim() throws`,
`isIdleDimmingSuspended: Bool?`, `setIdleDimmingSuspended(_:) throws`, `withIdleDimmingSuspended { }`,
`withManualControl { }` (sync + async),
`brightnessStream(pollInterval:preferPolling:)` (event-driven when available), `isBuiltIn`.
`Identifiable`, `Hashable`, `Sendable`.

**`KeyboardBacklight`** — `keyboards`, `defaultKeyboard`, `builtIn`, `discover() throws`
(reasoned failures via `DiscoveryError`), plus dynamic-member forwarding of every `Keyboard`
property. Types are `Double`/`TimeInterval` throughout; unsupported readings are `Optional`.

## Examples

Runnable via SPM — they `import BacklightKit`, so there's nothing to copy-paste:

```sh
swift run example-morse "HELLO WORLD" --unit 0.1   # blink a phrase in Morse
swift run example-typeglow                         # keyboard flares as you type; 'q' to quit
```

Source in [`examples/`](examples).

## How it works

The built-in keyboard backlight is a single PWM-driven white light guide, exposed in the
IORegistry as an `AppleARMPWMDevice` named `kbd-backlight` (Apple Silicon). Userspace controls it
through the private `KeyboardBrightnessClient` class in `CoreBrightness.framework`.

`backlit` `dlopen`s that framework and calls the class through the Objective-C runtime, so it
links against **nothing private at build time**. Capabilities are probed with `responds(to:)` at
startup, so "unsupported" surfaces as `nil` and `KeyboardBacklight()` returns `nil` on hardware
where the core selectors are missing — no crashes, no fake zeros.

## Platform & verification

**macOS only.** This wraps a macOS-private Apple framework and has no meaning on any other
OS — it won't build or run on Linux/Windows, and there's no cross-platform fallback.

**Only verified on Apple Silicon (M1).** I don't own any other Mac, so I can't test Intel
Macs, other Apple Silicon generations (M2/M3/M4), or other macOS versions. The code is written
defensively — every private call is capability-checked and degrades to `nil`/`false` rather
than crashing — so it *should* work anywhere with a backlit keyboard, but everything outside
the row below is **unverified**.

| Mac | Chip | macOS | Status |
|---|---|---|---|
| MacBook Air (2020) | Apple M1 | 26.x | ✅ read + write, nits, auto, idle-dim, events, suspend |

If you run it on other hardware, a PR adding a row (with your model + `sw_vers` build, and
whether it worked) is genuinely useful — it's the only way this table grows.
Behavior notes: built-in keyboards expose **one** white zone (no per-key/RGB); `idleDimTime = 0`
means idle dimming is **off**.

## FAQ

**Can I control individual keys / RGB like a gaming keyboard?**
No. The built-in keyboard is a single white zone with one brightness channel — no per-key
addressing and no color exist in the hardware. It's a physical limitation, not a software one.

**Does it need `sudo` or disabling SIP?**
No. It runs as a normal user with no special entitlements.

**Will an update break it?**
Possibly — it's a private API. Every call is defensive and the surface is tiny, so a changed
selector is a quick fix. Please open an issue with your macOS build if something regresses.

**Is it sandbox-safe?**
No. It relies on a private framework, so it's for CLI tools and menu-bar / agent utilities, not
App Store apps.

## Contributing

Issues and PRs welcome. CI builds and tests every PR on macOS; releases are cut automatically
when the version in `Sources/backlit/main.swift` changes on `main`. Good first contributions:
more verified hardware rows, additional CLI effects, and confirming behavior on Intel / Touch Bar Macs.

## License

[MIT](LICENSE) © totota-08

> Uses a private Apple framework via runtime lookup. Not affiliated with or endorsed by Apple.
