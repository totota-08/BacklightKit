# Changelog

All notable changes to this project are documented here. Releases are cut automatically
when the `version` in `Sources/kbdlight/main.swift` changes on `main`.

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
