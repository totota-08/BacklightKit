import Foundation

// MARK: - Errors & options

/// Errors thrown by the writable parts of the API.
public enum KeyboardBacklightError: Error, CustomStringConvertible {
    /// The underlying private call returned `false` (the system rejected the change).
    case setFailed
    /// The private selector this feature needs is not available on this OS/hardware.
    case unsupported(String)

    public var description: String {
        switch self {
        case .setFailed: return "the system rejected the change"
        case .unsupported(let s): return "unsupported on this Mac: \(s)"
        }
    }
}

/// Why `KeyboardBacklight.discover()` failed. `init?()` collapses these to `nil`;
/// use `discover()` when you need to tell a user (or a bug report) *why*.
public enum DiscoveryError: Error, CustomStringConvertible {
    /// The private CoreBrightness framework could not be loaded.
    case frameworkUnavailable
    /// `KeyboardBrightnessClient` no longer exists (private API changed).
    case clientClassUnavailable
    /// A selector the library cannot work without is missing (private API changed).
    case requiredSelectorMissing(String)
    /// The framework loaded fine but reports no backlight-capable keyboard
    /// (e.g. a desktop Mac, or clamshell mode with a non-backlit external keyboard).
    case noBacklitKeyboards

    public var description: String {
        switch self {
        case .frameworkUnavailable: return "CoreBrightness framework unavailable"
        case .clientClassUnavailable: return "KeyboardBrightnessClient class not found (private API changed)"
        case .requiredSelectorMissing(let s): return "required selector missing: \(s) (private API changed)"
        case .noBacklitKeyboards: return "no backlight-capable keyboard present"
        }
    }
}

/// How a brightness change is applied. `.instant` applies immediately (good for hard
/// blinks); the others ask the system to ramp. The exact ramp rate is Apple's, not ours.
public enum FadeSpeed: Sendable {
    case instant, slow, fast
    var raw: Int32 { switch self { case .instant: return 0; case .slow: return 1; case .fast: return 2 } }
}

// MARK: - Keyboard (the operable object)

/// A single backlight-capable keyboard. **This is the thing you operate on** —
/// `keyboard.brightness = 0.5`, `keyboard.setBrightness(1, fade: .slow)`, etc.
///
/// Error handling: every write has a throwing method (`setBrightness`,
/// `setAutoBrightness`, `setIdleDimTime`). The writable *properties* (`brightness`,
/// `autoBrightness`) are fire-and-forget conveniences that ignore failure — use the
/// throwing method when you need to know.
///
/// Concurrency: reads (`brightness`, `nits`, the status flags) are stateless calls into
/// the system and are safe from any thread — which is why `brightnessStream` can poll on
/// a background task, and why the type is `Sendable` (it holds no mutable state at all —
/// `@unchecked` exists only because the stored `NSObject` client can't be marked Sendable).
/// Writes go straight to the system too; "last write wins" if you race them.
public final class Keyboard: @unchecked Sendable, Identifiable {

    /// Opaque backlight identifier used by the private API. Stable for the lifetime of
    /// the containing `KeyboardBacklight`, not across reconnects or reboots.
    public let id: UInt64
    /// Whether this is the machine's built-in keyboard.
    public let isBuiltIn: Bool
    /// Whether the keyboard supports ambient-light-driven auto-brightness.
    /// See `autoBrightness` for whether it is currently enabled.
    public let supportsAutoBrightness: Bool

    private let client: NSObject
    // Capability flags, resolved once so "unsupported" and "value is 0" never get confused.
    private let canSetFade: Bool
    private let canSetPlain: Bool
    private let canNits: Bool
    private let canIdleDim: Bool
    private let canSaturated: Bool
    private let canSuppressed: Bool
    private let canDimmed: Bool

    init(id: UInt64, client: NSObject) {
        self.id = id
        self.client = client
        func has(_ s: String) -> Bool { client.responds(to: NSSelectorFromString(s)) }
        self.isBuiltIn              = Keyboard.boolCall(client, "isKeyboardBuiltIn:", id)
        self.supportsAutoBrightness = Keyboard.boolCall(client, "isAmbientFeatureAvailableOnKeyboard:", id)
        self.canSetFade       = has("setBrightness:fadeSpeed:commit:forKeyboard:")
        self.canSetPlain      = has("setBrightness:forKeyboard:")
        self.canNits          = has("backlightLevelForKeyboard:")
        self.canIdleDim       = has("idleDimTimeForKeyboard:")
        self.canSaturated     = has("isBacklightSaturatedOnKeyboard:")
        self.canSuppressed    = has("isBacklightSuppressedOnKeyboard:")
        self.canDimmed        = has("isBacklightDimmedOnKeyboard:")
    }

    // MARK: Brightness (0.0 ... 1.0)

    /// Current brightness, `0.0 ... 1.0`. The setter is a convenience that ignores
    /// failure; call `setBrightness(_:fade:)` when you need the error.
    public var brightness: Double {
        get { Double(floatCall("brightnessForKeyboard:")) }
        set { try? setBrightness(newValue) }
    }

    /// Set brightness (clamped to `0...1`). Throws if the system rejects it or the
    /// feature is unavailable.
    public func setBrightness(_ value: Double, fade: FadeSpeed = .instant) throws {
        let v = Float(max(0, min(1, value)))
        if canSetFade {
            let sel = NSSelectorFromString("setBrightness:fadeSpeed:commit:forKeyboard:")
            typealias Fn = @convention(c) (NSObject, Selector, Float, Int32, Bool, UInt64) -> Bool
            let ok = unsafeBitCast(client.method(for: sel), to: Fn.self)(client, sel, v, fade.raw, true, id)
            if !ok { throw KeyboardBacklightError.setFailed }
        } else if canSetPlain {
            let sel = NSSelectorFromString("setBrightness:forKeyboard:")
            typealias Fn = @convention(c) (NSObject, Selector, Float, UInt64) -> Bool
            let ok = unsafeBitCast(client.method(for: sel), to: Fn.self)(client, sel, v, id)
            if !ok { throw KeyboardBacklightError.setFailed }
        } else {
            throw KeyboardBacklightError.unsupported("setBrightness")
        }
    }

    // MARK: Physical light output

    /// Actual light output in **nits** (from Apple's calibration table), or `nil` if the
    /// system doesn't expose it. Read-only. Distinct from `brightness`, which is a 0–1 level.
    public var nits: Double? {
        canNits ? Double(floatCall("backlightLevelForKeyboard:")) : nil
    }

    // MARK: Auto (ambient) brightness

    /// Whether ambient auto-brightness is currently enabled. The setter is a convenience
    /// that ignores failure; call `setAutoBrightness(_:)` when you need the error.
    /// See `supportsAutoBrightness` for whether the keyboard has the feature at all.
    public var autoBrightness: Bool {
        get { boolCall("isAutoBrightnessEnabledForKeyboard:") }
        set { try? setAutoBrightness(newValue) }
    }

    /// Enable or disable ambient auto-brightness. Throws if the system rejects it or
    /// the feature is unavailable.
    public func setAutoBrightness(_ enabled: Bool) throws {
        let sel = NSSelectorFromString("enableAutoBrightness:forKeyboard:")
        guard client.responds(to: sel) else { throw KeyboardBacklightError.unsupported("setAutoBrightness") }
        typealias Fn = @convention(c) (NSObject, Selector, Bool, UInt64) -> Bool
        let ok = unsafeBitCast(client.method(for: sel), to: Fn.self)(client, sel, enabled, id)
        if !ok { throw KeyboardBacklightError.setFailed }
    }

    // MARK: Status flags (nil when the OS doesn't report them)

    /// Backlight is at its ambient-driven ceiling. `nil` if unsupported.
    public var isSaturated: Bool? { canSaturated ? boolCall("isBacklightSaturatedOnKeyboard:") : nil }
    /// Backlight is currently suppressed (bright room, policy, …). `nil` if unsupported.
    public var isSuppressed: Bool? { canSuppressed ? boolCall("isBacklightSuppressedOnKeyboard:") : nil }
    /// Backlight is dimmed due to user idle. `nil` if unsupported.
    public var isDimmed: Bool? { canDimmed ? boolCall("isBacklightDimmedOnKeyboard:") : nil }

    // MARK: Idle dim timeout

    /// Seconds of inactivity before the backlight dims. **`0` means idle dimming is
    /// disabled** (verified: the default is `0` and the keyboard stays lit). `nil` if
    /// unsupported. Read-only — change it with `setIdleDimTime(_:)` / `disableIdleDim()`.
    public var idleDimTime: TimeInterval? {
        canIdleDim ? doubleCall("idleDimTimeForKeyboard:") : nil
    }

    /// Set the idle-dim timeout in seconds (`0` disables idle dimming). Throws if the
    /// system rejects it or the feature is unavailable.
    public func setIdleDimTime(_ seconds: TimeInterval) throws {
        let sel = NSSelectorFromString("setIdleDimTime:forKeyboard:")
        guard client.responds(to: sel) else { throw KeyboardBacklightError.unsupported("setIdleDimTime") }
        typealias Fn = @convention(c) (NSObject, Selector, Double, UInt64) -> Bool
        let ok = unsafeBitCast(client.method(for: sel), to: Fn.self)(client, sel, seconds, id)
        if !ok { throw KeyboardBacklightError.setFailed }
    }

    /// Turn off idle-driven dimming (`setIdleDimTime(0)`).
    public func disableIdleDim() throws { try setIdleDimTime(0) }

    // MARK: Scoped manual control

    /// Run `body` with manual control: saves the current brightness + auto-brightness,
    /// disables auto so the ambient sensor won't fight you, and **always restores both**
    /// when the block exits — normally or by throwing.
    ///
    /// ```swift
    /// try keyboard.withManualControl { kb in
    ///     for _ in 0..<3 { try kb.setBrightness(1); usleep(120_000); try kb.setBrightness(0); usleep(120_000) }
    /// }
    /// ```
    @discardableResult
    public func withManualControl<T>(_ body: (Keyboard) throws -> T) rethrows -> T {
        let savedBrightness = brightness
        let savedAuto = autoBrightness
        try? setAutoBrightness(false)
        defer {
            try? setBrightness(savedBrightness)
            try? setAutoBrightness(savedAuto)
        }
        return try body(self)
    }

    /// Async variant of `withManualControl(_:)` — lets `body` use `Task.sleep` instead
    /// of blocking a thread. Same save/disable-auto/always-restore contract.
    ///
    /// ```swift
    /// try await keyboard.withManualControl { kb in
    ///     for _ in 0..<3 {
    ///         try kb.setBrightness(1); try await Task.sleep(nanoseconds: 120_000_000)
    ///         try kb.setBrightness(0); try await Task.sleep(nanoseconds: 120_000_000)
    ///     }
    /// }
    /// ```
    @discardableResult
    public func withManualControl<T>(_ body: (Keyboard) async throws -> T) async rethrows -> T {
        let savedBrightness = brightness
        let savedAuto = autoBrightness
        try? setAutoBrightness(false)
        defer {
            try? setBrightness(savedBrightness)
            try? setAutoBrightness(savedAuto)
        }
        return try await body(self)
    }

    // MARK: Change monitoring

    /// Emits the brightness whenever it changes, by polling every `pollInterval` seconds.
    /// (Apple's private change-notification selector exists but has an undocumented block
    /// signature; polling is the stable path.) The stream stops when its task is cancelled.
    public func brightnessStream(pollInterval: TimeInterval = 0.1) -> AsyncStream<Double> {
        AsyncStream { continuation in
            let task = Task.detached { [weak self] in
                var last = -1.0
                while !Task.isCancelled {
                    guard let self else { break }
                    let b = self.brightness
                    if abs(b - last) > 0.0005 { last = b; continuation.yield(b) }
                    try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Runtime trampolines

    private func floatCall(_ name: String) -> Float {
        let sel = NSSelectorFromString(name)
        guard client.responds(to: sel) else { return 0 }
        typealias Fn = @convention(c) (NSObject, Selector, UInt64) -> Float
        return unsafeBitCast(client.method(for: sel), to: Fn.self)(client, sel, id)
    }
    private func doubleCall(_ name: String) -> Double {
        let sel = NSSelectorFromString(name)
        guard client.responds(to: sel) else { return 0 }
        typealias Fn = @convention(c) (NSObject, Selector, UInt64) -> Double
        return unsafeBitCast(client.method(for: sel), to: Fn.self)(client, sel, id)
    }
    private func boolCall(_ name: String) -> Bool { Keyboard.boolCall(client, name, id) }
    fileprivate static func boolCall(_ client: NSObject, _ name: String, _ id: UInt64) -> Bool {
        let sel = NSSelectorFromString(name)
        guard client.responds(to: sel) else { return false }
        typealias Fn = @convention(c) (NSObject, Selector, UInt64) -> Bool
        return unsafeBitCast(client.method(for: sel), to: Fn.self)(client, sel, id)
    }
}

extension Keyboard: Equatable, Hashable {
    public static func == (lhs: Keyboard, rhs: Keyboard) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension Keyboard: CustomStringConvertible {
    public var description: String {
        "Keyboard(id: \(id)\(isBuiltIn ? ", built-in" : ""), brightness: \(String(format: "%.2f", brightness)))"
    }
}

// MARK: - KeyboardBacklight (entry point / discovery)

/// Entry point: discovers backlight-capable keyboards via Apple's **private**
/// `CoreBrightness` framework. No `sudo`, no entitlements, no SIP changes.
///
/// ```swift
/// guard let kb = KeyboardBacklight() else { return }   // nil if unsupported
/// kb.brightness = 1.0                                  // forwarded to defaultKeyboard
/// kb.builtIn?.brightness = 1.0
/// for keyboard in kb.keyboards { print(keyboard.id, keyboard.nits ?? -1) }
/// ```
///
/// Use `discover()` instead of `init?()` when you need to know *why* it failed.
/// All of `Keyboard`'s properties are forwarded to `defaultKeyboard` via dynamic member
/// lookup, so `kb.brightness`, `kb.nits`, `kb.autoBrightness`, … just work.
@dynamicMemberLookup
public final class KeyboardBacklight {

    /// Every backlight-capable keyboard currently present. Never empty.
    public let keyboards: [Keyboard]
    /// The keyboard the convenience accessors target. Prefers the built-in one.
    public let defaultKeyboard: Keyboard
    /// The built-in keyboard, if present.
    public var builtIn: Keyboard? { keyboards.first(where: { $0.isBuiltIn }) }

    private init(keyboards: [Keyboard], defaultKeyboard: Keyboard) {
        self.keyboards = keyboards
        self.defaultKeyboard = defaultKeyboard
    }

    /// Discover keyboards, or `nil` on any failure. Use `discover()` for the reason.
    public convenience init?() {
        guard let (keyboards, def) = try? KeyboardBacklight.performDiscovery() else { return nil }
        self.init(keyboards: keyboards, defaultKeyboard: def)
    }

    /// Discover keyboards, throwing a `DiscoveryError` that says what went wrong —
    /// missing framework, changed private API, or simply no backlit keyboard.
    public static func discover() throws -> KeyboardBacklight {
        let (keyboards, def) = try performDiscovery()
        return KeyboardBacklight(keyboards: keyboards, defaultKeyboard: def)
    }

    private static func performDiscovery() throws -> ([Keyboard], Keyboard) {
        guard dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW) != nil
        else { throw DiscoveryError.frameworkUnavailable }
        guard let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type
        else { throw DiscoveryError.clientClassUnavailable }
        let client = cls.init()

        for required in ["copyKeyboardBacklightIDs", "brightnessForKeyboard:"]
        where !client.responds(to: NSSelectorFromString(required)) {
            throw DiscoveryError.requiredSelectorMissing(required)
        }
        let idsSel = NSSelectorFromString("copyKeyboardBacklightIDs")
        guard let ids = client.perform(idsSel)?.takeRetainedValue() as? [NSNumber], !ids.isEmpty
        else { throw DiscoveryError.noBacklitKeyboards }

        let keyboards = ids.map { Keyboard(id: $0.uint64Value, client: client) }
        return (keyboards, keyboards.first(where: { $0.isBuiltIn }) ?? keyboards[0])
    }

    // MARK: Forwarding to the default keyboard

    /// Read-only forwarding: `kb.nits`, `kb.isSaturated`, …
    public subscript<T>(dynamicMember keyPath: KeyPath<Keyboard, T>) -> T {
        defaultKeyboard[keyPath: keyPath]
    }

    /// Read-write forwarding: `kb.brightness = 0.5`, `kb.autoBrightness = false`, …
    public subscript<T>(dynamicMember keyPath: ReferenceWritableKeyPath<Keyboard, T>) -> T {
        get { defaultKeyboard[keyPath: keyPath] }
        set { defaultKeyboard[keyPath: keyPath] = newValue }
    }

    // Methods aren't covered by dynamic member lookup — forward the main ones.
    public func setBrightness(_ value: Double, fade: FadeSpeed = .instant) throws {
        try defaultKeyboard.setBrightness(value, fade: fade)
    }
    @discardableResult
    public func withManualControl<T>(_ body: (Keyboard) throws -> T) rethrows -> T {
        try defaultKeyboard.withManualControl(body)
    }
    @discardableResult
    public func withManualControl<T>(_ body: (Keyboard) async throws -> T) async rethrows -> T {
        try await defaultKeyboard.withManualControl(body)
    }
}
