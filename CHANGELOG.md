# Changelog

All notable changes to this project are documented here. Releases are cut automatically
when the `version` in `Sources/backlit/main.swift` changes on `main`.

## 0.3.0

API-quality pass and a rename. **Breaking** — the public surface was reshaped while
still in 0.x; migration is mechanical (see below).

### Renamed
- **The project is now BacklightKit** (repo `totota-08/BacklightKit`): the Swift module
  `MacKeyboardBacklight` → **`BacklightKit`**, the CLI `kbdlight` → **`backlit`**, and the
  Homebrew formula → `totota-08/tap/backlit`. Class names (`KeyboardBacklight`, `Keyboard`)
  are unchanged. GitHub redirects the old repo URL; update SPM dependencies to the new URL.

### Changed (breaking)
- **One error story**: every write now has a throwing method — `setAutoBrightness(_:)`
  and `setIdleDimTime(_:)`/`disableIdleDim()` now `throw` instead of returning `Bool`.
  The writable properties (`brightness`, `autoBrightness`) are documented fire-and-forget
  conveniences. `lastSetError` is gone — use `setBrightness(_:fade:)` when you need the error.
- **`Morse.pulses(for:)` returns `Morse.Encoding`** (a struct with `pulses` + `skipped`)
  instead of a tuple, so fields can be added without breaking callers.
- **`idleDimTime` is read-only** — `= nil` used to be a silent no-op trap. Change it with
  `setIdleDimTime(_:)` / `disableIdleDim()`.
- **`supportsAmbient` → `supportsAutoBrightness`** — one term for the feature everywhere
  (`info` output and `--json` key renamed accordingly).
- **`FadeSpeed.none` → `.instant`** — says what it does and can never collide with
  `Optional.none` in inference contexts.
- Time values are typed `TimeInterval` (still `Double` under the hood).

### Added
- **`KeyboardBacklight.discover() throws`** — like `init?()` but tells you *why* discovery
  failed (`DiscoveryError`: framework missing / private API changed / no backlit keyboard).
  The CLI now uses it, so `kbdlight` error messages name the actual cause.
- **Dynamic member forwarding**: `KeyboardBacklight` forwards *every* `Keyboard` property
  to `defaultKeyboard` via `@dynamicMemberLookup` — no more hand-maintained mirror that
  could drift out of sync.
- **`withManualControl` async overload** — use `Task.sleep` instead of blocking a thread.
- `Keyboard` is now `Identifiable`, `Hashable`, `Equatable` (by `id`) and
  `CustomStringConvertible` — `kb.keyboards` drops straight into SwiftUI's `ForEach`.
- `Keyboard` is `Sendable` for real now (no mutable state at all).

### Changed
- The CLI's `pulse` and `morse` are rebuilt on `withManualControl` (the library's own
  restore machinery) instead of hand-rolling save/restore.

## 0.2.1

Follow-up fixes from code review.

### Fixed
- **Morse spacing**: text is now split into words first, so leading / trailing / repeated
  spaces can't leave a stray 7-unit dark gap on the ends or double a word gap to 14 units.
  Playback never begins or ends on an off-pulse. Added tests for these cases.
- **`morse` and `fade` now restore state on `Ctrl-C` / `SIGTERM`**, via a shared signal
  helper (previously only `pulse` did). Interrupting a long send no longer leaves the
  backlight stuck on or off.
- **`kbdlight set --fade 0.5`** (flag before value) no longer errors — flags are parsed
  independently of position.

### Added
- **`--keyboard <id>`** global flag to target a non-default keyboard from the CLI
  (the library was already multi-keyboard; now the CLI matches).

### Changed
- Removed a dead `stop` variable in `pulse`; documented `Keyboard`'s `@unchecked Sendable`
  contract (safe reads; confine writes to one thread); `example-typeglow` now catches SIGTERM
  and its restore comment no longer overclaims.

## 0.2.0

API redesign — subject-first, safer, and Homebrew/CI ready.

### Added
- **`Keyboard` is now the operable subject**: `keyboard.brightness = 1`,
  `keyboard.setBrightness(_:fade:)`, per-keyboard status flags — no more `of:` labels.
- `KeyboardBacklight.builtIn` and renamed `defaultKeyboard` (was `default`).
- `withManualControl { }` — saves brightness + auto-brightness, disables auto, and always
  restores on exit (normal or throwing).
- Throwing `setBrightness(_:fade:)` and `lastSetError` so set failures are observable.
- `FadeSpeed` enum (`.none` / `.slow` / `.fast`) replaces the `fade: Bool` flag.
- `brightnessStream(pollInterval:)` — an `AsyncStream<Double>` of brightness changes.
- `disableIdleDim()`; documented that `idleDimTime = 0` disables idle dimming (verified).
- CLI `morse <text>` command (shared `Morse` type: ITU timing, skips unknown chars,
  prints total duration).
- GitHub Actions: CI (build + test on PRs) and automatic Release on `main`.
- Unit tests for the pure Morse logic.

### Changed
- `level` → **`nits`**; all numeric types unified to `Double`.
- Unsupported readings return `Optional` (`nits`, `idleDimTime`, status flags) instead of a
  fake `0` / `false`, so "unsupported" and "genuinely zero" are distinguishable.
- Examples converted from a copy-paste Playground to SPM executables that `import` the library
  (`swift run example-morse`, `swift run example-typeglow`), with `responds(to:)` guards and
  reliable restore.

## 0.1.0

- Initial release: `MacKeyboardBacklight` library + `kbdlight` CLI over the private
  `CoreBrightness` / `KeyboardBrightnessClient` API.
