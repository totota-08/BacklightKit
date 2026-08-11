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
        case .setFailed: return "the system rejected the brightness change"
        case .unsupported(let s): return "unsupported on this Mac: \(s)"
        }
    }
}

/// How a brightness change is applied. `.none` is instantaneous (good for hard blinks);
/// the others ask the system to ramp. The exact ramp rate is Apple's, not ours.
public enum FadeSpeed: Sendable {
    case none, slow, fast
    var raw: Int32 { switch self { case .none: return 0; case .slow: return 1; case .fast: return 2 } }
}

// MARK: - Keyboard (the operable object)

/// A single backlight-capable keyboard. **This is the thing you operate on** —
/// `keyboard.brightness = 0.5`, `keyboard.setBrightness(1, fade: .slow)`, etc.
///
/// Not internally synchronized. Treat one instance as owned by a single thread/task
/// (the main actor is a fine choice). `brightnessStream` reads on a background task and
/// is the one intentional exception.
public final class Keyboard: @unchecked Sendable {

    /// Opaque backlight identifier used by the private API.
    public let id: UInt64
    /// Whether this is the machine's built-in keyboard.
    public let isBuiltIn: Bool
    /// Whether the keyboard reports an ambient-light sensor / auto-brightness support.
    public let supportsAmbient: Bool

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
        self.isBuiltIn        = Keyboard.boolCall(client, "isKeyboardBuiltIn:", id)
        self.supportsAmbient  = Keyboard.boolCall(client, "isAmbientFeatureAvailableOnKeyboard:", id)
        self.canSetFade       = has("setBrightness:fadeSpeed:commit:forKeyboard:")
        self.canSetPlain      = has("setBrightness:forKeyboard:")
        self.canNits          = has("backlightLevelForKeyboard:")
        self.canIdleDim       = has("idleDimTimeForKeyboard:")
        self.canSaturated     = has("isBacklightSaturatedOnKeyboard:")
        self.canSuppressed    = has("isBacklightSuppressedOnKeyboard:")
        self.canDimmed        = has("isBacklightDimmedOnKeyboard:")
    }

    // MARK: Brightness (0.0 ... 1.0)

    /// The last error produced by the `brightness` property setter (which cannot throw).
    /// `nil` after a successful set. For explicit handling, use `setBrightness(_:fade:)`.
    public private(set) var lastSetError: KeyboardBacklightError?

    /// Current brightness, `0.0 ... 1.0`. The setter swallows failures — check
    /// `lastSetError`, or call the throwing `setBrightness(_:fade:)` instead.
    public var brightness: Double {
        get { Double(floatCall("brightnessForKeyboard:")) }
        set {
            do { try setBrightness(newValue); lastSetError = nil }
            catch { lastSetError = error as? KeyboardBacklightError }
        }
    }

    /// Set brightness (clamped to `0...1`). Throws if the system rejects it or the
    /// feature is unavailable.
    public func setBrightness(_ value: Double, fade: FadeSpeed = .none) throws {
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

    /// Whether ambient auto-brightness is enabled. See `supportsAmbient` to know if the
    /// keyboard has the feature at all.
    public var autoBrightness: Bool {
        get { boolCall("isAutoBrightnessEnabledForKeyboard:") }
        set { setAutoBrightness(newValue) }
    }

    @discardableResult
    public func setAutoBrightness(_ enabled: Bool) -> Bool {
        let sel = NSSelectorFromString("enableAutoBrightness:forKeyboard:")
        guard client.responds(to: sel) else { return false }
        typealias Fn = @convention(c) (NSObject, Selector, Bool, UInt64) -> Bool
        return unsafeBitCast(client.method(for: sel), to: Fn.self)(client, sel, enabled, id)
    }

    // MARK: Status flags (nil when the OS doesn't report them)

    /// Backlight is at its ambient-driven ceiling. `nil` if unsupported.
    public var isSaturated: Bool? { canSaturated ? boolCall("isBacklightSaturatedOnKeyboard:") : nil }
    /// Backlight is currently suppressed (bright room, policy, …). `nil` if unsupported.
    public var isSuppressed: Bool? { canSuppressed ? boolCall("isBacklightSuppressedOnKeyboard:") : nil }
    /// Backlight is dimmed due to user idle. `nil` if unsupported.
    public var isDimmed: Bool? { canDimmed ? boolCall("isBacklightDimmedOnKeyboard:") : nil }

    // MARK: Idle dim timeout

    /// Seconds of inactivity before the backlight dims. **`0` disables idle dimming**
    /// (verified: the default is `0` and the keyboard stays lit). `nil` if unsupported.
    public var idleDimTime: Double? {
        get { canIdleDim ? doubleCall("idleDimTimeForKeyboard:") : nil }
        set { if let v = newValue { _ = setIdleDimTime(v) } }
    }

    @discardableResult
    public func setIdleDimTime(_ seconds: Double) -> Bool {
        let sel = NSSelectorFromString("setIdleDimTime:forKeyboard:")
        guard client.responds(to: sel) else { return false }
        typealias Fn = @convention(c) (NSObject, Selector, Double, UInt64) -> Bool
        return unsafeBitCast(client.method(for: sel), to: Fn.self)(client, sel, seconds, id)
    }

    /// Turn off idle-driven dimming (`idleDimTime = 0`).
    @discardableResult public func disableIdleDim() -> Bool { setIdleDimTime(0) }

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
        setAutoBrightness(false)
        defer {
            try? setBrightness(savedBrightness)
            setAutoBrightness(savedAuto)
        }
        return try body(self)
    }

    // MARK: Change monitoring

    /// Emits the brightness whenever it changes, by polling every `pollInterval` seconds.
    /// (Apple's private change-notification selector exists but has an undocumented block
    /// signature; polling is the stable path.) The stream stops when its task is cancelled.
    public func brightnessStream(pollInterval: Double = 0.1) -> AsyncStream<Double> {
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

// MARK: - KeyboardBacklight (entry point / discovery)

/// Entry point: discovers backlight-capable keyboards via Apple's **private**
/// `CoreBrightness` framework. No `sudo`, no entitlements, no SIP changes.
///
/// ```swift
/// guard let kb = KeyboardBacklight() else { return }   // nil if unsupported
/// kb.builtIn?.brightness = 1.0
/// for keyboard in kb.keyboards { print(keyboard.id, keyboard.nits ?? -1) }
/// ```
///
/// The convenience accessors (`brightness`, `nits`, …) forward to `defaultKeyboard`.
public final class KeyboardBacklight {

    /// Every backlight-capable keyboard currently present. May be empty (e.g. clamshell
    /// mode with only a non-backlit external keyboard) — in that case `init` returns `nil`.
    public let keyboards: [Keyboard]
    /// The keyboard the convenience accessors target. Prefers the built-in one.
    public let defaultKeyboard: Keyboard
    /// The built-in keyboard, if present.
    public var builtIn: Keyboard? { keyboards.first(where: { $0.isBuiltIn }) }

    public init?() {
        guard dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW) != nil,
              let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type
        else { return nil }
        let client = cls.init()

        let idsSel = NSSelectorFromString("copyKeyboardBacklightIDs")
        guard client.responds(to: idsSel),
              client.responds(to: NSSelectorFromString("brightnessForKeyboard:")),
              let ids = client.perform(idsSel)?.takeRetainedValue() as? [NSNumber],
              !ids.isEmpty
        else { return nil }

        keyboards = ids.map { Keyboard(id: $0.uint64Value, client: client) }
        defaultKeyboard = keyboards.first(where: { $0.isBuiltIn }) ?? keyboards[0]
    }

    // Convenience forwarding to the default keyboard.
    public var brightness: Double {
        get { defaultKeyboard.brightness }
        set { defaultKeyboard.brightness = newValue }
    }
    public func setBrightness(_ v: Double, fade: FadeSpeed = .none) throws {
        try defaultKeyboard.setBrightness(v, fade: fade)
    }
    public var nits: Double? { defaultKeyboard.nits }
    public var autoBrightness: Bool {
        get { defaultKeyboard.autoBrightness }
        set { defaultKeyboard.autoBrightness = newValue }
    }
    public var idleDimTime: Double? {
        get { defaultKeyboard.idleDimTime }
        set { defaultKeyboard.idleDimTime = newValue }
    }
    public var isSaturated: Bool? { defaultKeyboard.isSaturated }
    public var isSuppressed: Bool? { defaultKeyboard.isSuppressed }
    public var isDimmed: Bool? { defaultKeyboard.isDimmed }
    @discardableResult
    public func withManualControl<T>(_ body: (Keyboard) throws -> T) rethrows -> T {
        try defaultKeyboard.withManualControl(body)
    }
}
