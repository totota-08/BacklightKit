import Foundation

// MARK: - Errors & options

/// Errors thrown by the writable parts of the API.
///
/// May gain cases in future versions (this wraps a private API whose failure modes can
/// grow) — include a `default` when switching exhaustively.
public enum KeyboardBacklightError: Error, CustomStringConvertible, LocalizedError {
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
    public var errorDescription: String? { description }
}

/// Why `KeyboardBacklight.discover()` failed. `init?()` collapses these to `nil`;
/// use `discover()` when you need to tell a user (or a bug report) *why*.
///
/// May gain cases in future versions (Apple's private API can grow new failure modes) —
/// include a `default` when switching exhaustively.
public enum DiscoveryError: Error, CustomStringConvertible, LocalizedError {
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
    public var errorDescription: String? { description }
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
    private let canSuspendIdleDim: Bool
    private let canNotify: Bool

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
        self.canSuspendIdleDim = has("suspendIdleDimming:forKeyboard:") && has("isIdleDimmingSuspendedOnKeyboard:")
        self.canNotify        = has("registerNotificationForKeys:keyboardID:block:")
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
    /// (If the OS is missing the underlying getter entirely, this reads as `false`.)
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

    // MARK: Idle-dim suspend (temporary, non-destructive)

    /// Whether idle dimming is currently *suspended*. This is distinct from `idleDimTime`:
    /// suspending pauses the dimming timer without changing its configured value, so the
    /// original timeout resumes when you unsuspend. `nil` if unsupported.
    public var isIdleDimmingSuspended: Bool? {
        canSuspendIdleDim ? boolCall("isIdleDimmingSuspendedOnKeyboard:") : nil
    }

    /// Suspend or resume idle dimming without touching the configured `idleDimTime` — use
    /// this to keep the keyboard lit through a presentation, then hand control back
    /// exactly as it was. Prefer `withIdleDimmingSuspended(_:)` for automatic restore.
    /// Throws if the system rejects it or the feature is unavailable.
    public func setIdleDimmingSuspended(_ suspended: Bool) throws {
        let sel = NSSelectorFromString("suspendIdleDimming:forKeyboard:")
        guard canSuspendIdleDim else { throw KeyboardBacklightError.unsupported("suspendIdleDimming") }
        typealias Fn = @convention(c) (NSObject, Selector, Bool, UInt64) -> Bool
        let ok = unsafeBitCast(client.method(for: sel), to: Fn.self)(client, sel, suspended, id)
        if !ok { throw KeyboardBacklightError.setFailed }
    }

    /// Run `body` with idle dimming suspended, then restore the previous suspend state —
    /// even if `body` throws. Unlike `withManualControl`, this leaves brightness and
    /// auto-brightness untouched; it only pauses the idle-dim timer.
    ///
    /// ```swift
    /// try keyboard.withIdleDimmingSuspended {
    ///     runLongPresentation()          // keyboard stays lit the whole time
    /// }
    /// ```
    @discardableResult
    public func withIdleDimmingSuspended<T>(_ body: () throws -> T) throws -> T {
        guard canSuspendIdleDim else { throw KeyboardBacklightError.unsupported("suspendIdleDimming") }
        let wasSuspended = isIdleDimmingSuspended ?? false
        try setIdleDimmingSuspended(true)
        defer { try? setIdleDimmingSuspended(wasSuspended) }
        return try body()
    }

    // MARK: Scoped manual control

    /// Run `body` with manual control: saves the current brightness + auto-brightness,
    /// disables auto so the ambient sensor won't fight you, and **always attempts to
    /// restore both** when the block exits — normally or by throwing (restore failures
    /// are swallowed; there is nowhere left to report them).
    ///
    /// Not reentrant: two overlapping `withManualControl` blocks on the same keyboard
    /// would save/restore each other's state — run them one at a time.
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

    /// Emits the current brightness first, then again on every change.
    ///
    /// When the OS exposes its change-notification selector (verified on macOS 12+), this
    /// is **event-driven** — the system pushes each change, so there is no polling and no
    /// latency, and `pollInterval` is ignored. On systems where that selector is missing it
    /// falls back to polling every `pollInterval` seconds (clamped to ≥ 0.01). Pass
    /// `preferPolling: true` to force the polling path.
    ///
    /// The stream ends when the consuming task is cancelled. It retains what it needs, so
    /// `discover()?.defaultKeyboard.brightnessStream()` works without keeping your own
    /// reference.
    public func brightnessStream(pollInterval: TimeInterval = 0.1,
                                 preferPolling: Bool = false) -> AsyncStream<Double> {
        if canNotify, !preferPolling, let stream = notificationStream() { return stream }
        return pollingStream(pollInterval: pollInterval)
    }

    /// Event-driven path: a dedicated private client with its own notification block, so it
    /// never disturbs the shared client's registrations. `nil` if a fresh client can't be made.
    private func notificationStream() -> AsyncStream<Double>? {
        guard let notifyClient = KeyboardBacklight.newBrightnessClient() else { return nil }
        let regSel = NSSelectorFromString("registerNotificationForKeys:keyboardID:block:")
        guard notifyClient.responds(to: regSel) else { return nil }
        let kid = id
        return AsyncStream { continuation in
            // Push the current value up front, matching the polling path's contract.
            continuation.yield(self.brightness)

            let block: @convention(block) (AnyObject?, AnyObject?) -> Void = { _, value in
                if let n = value as? NSNumber { continuation.yield(n.doubleValue) }
            }
            let keys = ["KeyboardBacklightBrightness"] as NSArray
            typealias Reg = @convention(c) (NSObject, Selector, NSArray, UInt64, AnyObject) -> Void
            unsafeBitCast(notifyClient.method(for: regSel), to: Reg.self)(notifyClient, regSel, keys, kid, block as AnyObject)

            continuation.onTermination = { _ in
                let unregSel = NSSelectorFromString("unregisterKeyboardNotificationBlock")
                if notifyClient.responds(to: unregSel) { notifyClient.perform(unregSel) }
            }
        }
    }

    /// Polling fallback: sample brightness every `pollInterval` seconds.
    private func pollingStream(pollInterval: TimeInterval) -> AsyncStream<Double> {
        let interval = max(0.01, pollInterval)
        return AsyncStream { continuation in
            let task = Task.detached {
                var last = -1.0
                while !Task.isCancelled {
                    let b = self.brightness
                    if abs(b - last) > 0.0005 { last = b; continuation.yield(b) }
                    try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
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
public final class KeyboardBacklight: Sendable {

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

    /// Create a fresh `KeyboardBrightnessClient` instance (the private facade), or `nil`.
    /// Used to give the change-notification stream its own client so it never disturbs the
    /// shared client's registrations. `dlopen` is idempotent, so this is cheap to repeat.
    static func newBrightnessClient() -> NSObject? {
        guard dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW) != nil,
              let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type
        else { return nil }
        return cls.init()
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

    // Methods aren't covered by dynamic member lookup — forward ALL of them, so the rule
    // stays simple: everything on Keyboard also works on KeyboardBacklight.
    public func setBrightness(_ value: Double, fade: FadeSpeed = .instant) throws {
        try defaultKeyboard.setBrightness(value, fade: fade)
    }
    public func setAutoBrightness(_ enabled: Bool) throws {
        try defaultKeyboard.setAutoBrightness(enabled)
    }
    public func setIdleDimTime(_ seconds: TimeInterval) throws {
        try defaultKeyboard.setIdleDimTime(seconds)
    }
    public func disableIdleDim() throws {
        try defaultKeyboard.disableIdleDim()
    }
    public func setIdleDimmingSuspended(_ suspended: Bool) throws {
        try defaultKeyboard.setIdleDimmingSuspended(suspended)
    }
    @discardableResult
    public func withIdleDimmingSuspended<T>(_ body: () throws -> T) throws -> T {
        try defaultKeyboard.withIdleDimmingSuspended(body)
    }
    public func brightnessStream(pollInterval: TimeInterval = 0.1,
                                 preferPolling: Bool = false) -> AsyncStream<Double> {
        defaultKeyboard.brightnessStream(pollInterval: pollInterval, preferPolling: preferPolling)
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
