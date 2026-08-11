# Changelog

All notable changes to this project are documented here. Releases are cut automatically
when the `version` in `Sources/kbdlight/main.swift` changes on `main`.

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
