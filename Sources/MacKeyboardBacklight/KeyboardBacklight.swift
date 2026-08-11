import Foundation

/// A single backlight-capable keyboard reported by the system.
public struct Keyboard: Equatable, Sendable {
    /// Opaque backlight identifier used by the private API.
    public let id: UInt64
    /// Whether this is the machine's built-in keyboard.
    public let isBuiltIn: Bool
    /// Whether ambient (automatic) brightness is supported on this keyboard.
    public let ambientFeatureAvailable: Bool
}

/// Controls the built-in (and any attached) keyboard backlight on Apple hardware.
///
/// This wraps Apple's **private** `CoreBrightness.framework` / `KeyboardBrightnessClient`.
/// It needs no `sudo`, no entitlements, and no SIP changes — it runs as a normal user.
/// Because the API is private it may change or vanish in a future macOS; every call
/// is defensive and degrades gracefully.
///
/// ```swift
/// guard let kb = KeyboardBacklight() else { return }   // nil if unsupported
/// print(kb.brightness)        // 0.0 ... 1.0
/// kb.brightness = 0.5         // set to 50%
/// kb.setBrightness(1.0, fade: true)
/// ```
public final class KeyboardBacklight {

    private let client: NSObject

    /// Every backlight-capable keyboard currently present.
    public let keyboards: [Keyboard]

    /// The keyboard targeted by the convenience accessors. Prefers the built-in one.
    public let `default`: Keyboard

    /// Creates a controller, or returns `nil` if the private framework is missing,
    /// the class is unavailable, or no controllable keyboard exists.
    public init?() {
        guard dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW) != nil,
              let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type
        else { return nil }
        let c = cls.init()
        client = c

        let idsSel = NSSelectorFromString("copyKeyboardBacklightIDs")
        guard c.responds(to: idsSel),
              let ids = c.perform(idsSel)?.takeRetainedValue() as? [NSNumber],
              !ids.isEmpty
        else { return nil }

        keyboards = ids.map { n in
            let id = n.uint64Value
            return Keyboard(
                id: id,
                isBuiltIn: KeyboardBacklight.boolCall(c, "isKeyboardBuiltIn:", id),
                ambientFeatureAvailable: KeyboardBacklight.boolCall(c, "isAmbientFeatureAvailableOnKeyboard:", id)
            )
        }
        `default` = keyboards.first(where: { $0.isBuiltIn }) ?? keyboards[0]
    }

    // MARK: - Brightness (0.0 ... 1.0)

    /// Brightness of the default keyboard, clamped to `0.0 ... 1.0`.
    public var brightness: Float {
        get { brightness(of: `default`) }
        set { setBrightness(newValue, of: `default`) }
    }

    /// Brightness of a specific keyboard, `0.0 ... 1.0`.
    public func brightness(of keyboard: Keyboard) -> Float {
        floatCall("brightnessForKeyboard:", keyboard.id)
    }

    /// Sets brightness (clamped to `0...1`). When `fade` is false the change is
    /// instantaneous — useful for hard blinks the system would otherwise smooth.
    @discardableResult
    public func setBrightness(_ value: Float, of keyboard: Keyboard? = nil, fade: Bool = false) -> Bool {
        let id = (keyboard ?? `default`).id
        let v = max(0, min(1, value))
        let fadeSel = NSSelectorFromString("setBrightness:fadeSpeed:commit:forKeyboard:")
        if client.responds(to: fadeSel) {
            typealias Fn = @convention(c) (NSObject, Selector, Float, Int32, Bool, UInt64) -> Bool
            let fn = unsafeBitCast(client.method(for: fadeSel), to: Fn.self)
            return fn(client, fadeSel, v, fade ? 1 : 0, true, id)
        }
        let sel = NSSelectorFromString("setBrightness:forKeyboard:")
        guard client.responds(to: sel) else { return false }
        typealias Fn = @convention(c) (NSObject, Selector, Float, UInt64) -> Bool
        let fn = unsafeBitCast(client.method(for: sel), to: Fn.self)
        return fn(client, sel, v, id)
    }

    // MARK: - Physical level (nits, read-only)

    /// The keyboard's actual light output in **nits**, as reported by the system's
    /// calibration table. Read-only.
    public var level: Float { level(of: `default`) }

    /// Physical light output in nits for a specific keyboard.
    public func level(of keyboard: Keyboard) -> Float {
        floatCall("backlightLevelForKeyboard:", keyboard.id)
    }

    // MARK: - Automatic (ambient) brightness

    /// Whether ambient-light auto brightness is enabled on the default keyboard.
    public var autoBrightness: Bool {
        get { boolCall("isAutoBrightnessEnabledForKeyboard:", `default`.id) }
        set { setAutoBrightness(newValue) }
    }

    @discardableResult
    public func setAutoBrightness(_ enabled: Bool, of keyboard: Keyboard? = nil) -> Bool {
        let id = (keyboard ?? `default`).id
        let sel = NSSelectorFromString("enableAutoBrightness:forKeyboard:")
        guard client.responds(to: sel) else { return false }
        typealias Fn = @convention(c) (NSObject, Selector, Bool, UInt64) -> Bool
        let fn = unsafeBitCast(client.method(for: sel), to: Fn.self)
        return fn(client, sel, enabled, id)
    }

    // MARK: - Status flags

    /// The backlight is at its ambient-driven ceiling (can't auto-go brighter).
    public var isSaturated: Bool { boolCall("isBacklightSaturatedOnKeyboard:", `default`.id) }
    /// The backlight is currently suppressed (e.g. bright room, lid, or policy).
    public var isSuppressed: Bool { boolCall("isBacklightSuppressedOnKeyboard:", `default`.id) }
    /// The backlight is dimmed due to user idle.
    public var isDimmed: Bool { boolCall("isBacklightDimmedOnKeyboard:", `default`.id) }

    // MARK: - Idle dim timeout

    /// Seconds of inactivity before the backlight dims. `0` means never / immediate.
    public var idleDimTime: TimeInterval {
        get { doubleCall("idleDimTimeForKeyboard:", `default`.id) }
        set { setIdleDimTime(newValue) }
    }

    @discardableResult
    public func setIdleDimTime(_ seconds: TimeInterval, of keyboard: Keyboard? = nil) -> Bool {
        let id = (keyboard ?? `default`).id
        let sel = NSSelectorFromString("setIdleDimTime:forKeyboard:")
        guard client.responds(to: sel) else { return false }
        typealias Fn = @convention(c) (NSObject, Selector, Double, UInt64) -> Bool
        let fn = unsafeBitCast(client.method(for: sel), to: Fn.self)
        return fn(client, sel, seconds, id)
    }

    // MARK: - Runtime trampolines

    private func floatCall(_ name: String, _ id: UInt64) -> Float {
        let sel = NSSelectorFromString(name)
        guard client.responds(to: sel) else { return 0 }
        typealias Fn = @convention(c) (NSObject, Selector, UInt64) -> Float
        return unsafeBitCast(client.method(for: sel), to: Fn.self)(client, sel, id)
    }

    private func doubleCall(_ name: String, _ id: UInt64) -> Double {
        let sel = NSSelectorFromString(name)
        guard client.responds(to: sel) else { return 0 }
        typealias Fn = @convention(c) (NSObject, Selector, UInt64) -> Double
        return unsafeBitCast(client.method(for: sel), to: Fn.self)(client, sel, id)
    }

    private func boolCall(_ name: String, _ id: UInt64) -> Bool {
        KeyboardBacklight.boolCall(client, name, id)
    }

    private static func boolCall(_ client: NSObject, _ name: String, _ id: UInt64) -> Bool {
        let sel = NSSelectorFromString(name)
        guard client.responds(to: sel) else { return false }
        typealias Fn = @convention(c) (NSObject, Selector, UInt64) -> Bool
        return unsafeBitCast(client.method(for: sel), to: Fn.self)(client, sel, id)
    }
}
