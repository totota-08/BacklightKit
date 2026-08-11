import Foundation

//  TypeGlow — 打鍵するたびキーボードバックライトがフワッと光り、指を止めると暗くなる。
//  タイピングのリズムがそのまま光になる “type-to-glow” サンプル。
//
//  実行:  swift examples/TypeGlow.swift
//  終了:  q または Ctrl-C（元の明るさ・自動調光に戻す）
//
//  依存ゼロ・sudo/SIP 不要。Accessibility 権限も不要（このターミナルへの入力だけを見る）。

// MARK: - 内蔵キーボードバックライト（private CoreBrightness framework）
final class KeyboardBacklight {
    private let client: NSObject
    private let id: UInt64
    init?() {
        guard dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW) != nil,
              let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else { return nil }
        client = cls.init()
        let sel = NSSelectorFromString("copyKeyboardBacklightIDs")
        guard let ids = client.perform(sel)?.takeRetainedValue() as? [NSNumber], let f = ids.first else { return nil }
        id = f.uint64Value
    }
    var brightness: Float {
        get {
            let s = NSSelectorFromString("brightnessForKeyboard:")
            typealias F = @convention(c) (NSObject, Selector, UInt64) -> Float
            return unsafeBitCast(client.method(for: s), to: F.self)(client, s, id)
        }
        set {
            let s = NSSelectorFromString("setBrightness:fadeSpeed:commit:forKeyboard:")
            typealias F = @convention(c) (NSObject, Selector, Float, Int32, Bool, UInt64) -> Bool
            _ = unsafeBitCast(client.method(for: s), to: F.self)(client, s, max(0, min(1, newValue)), 0, true, id)
        }
    }
    func setAuto(_ on: Bool) {
        let s = NSSelectorFromString("enableAutoBrightness:forKeyboard:")
        typealias F = @convention(c) (NSObject, Selector, Bool, UInt64) -> Bool
        _ = unsafeBitCast(client.method(for: s), to: F.self)(client, s, on, id)
    }
}

guard let kb = KeyboardBacklight() else {
    FileHandle.standardError.write(Data("no keyboard backlight on this Mac\n".utf8)); exit(1)
}

let savedBrightness = kb.brightness
kb.setAuto(false)

// 現在の光量。打鍵で 1.0 に跳ね上がり、時間で減衰する。
let lock = NSLock()
var glow: Float = 0
var stopped = false

func restoreAndExit() -> Never {
    lock.lock(); stopped = true; lock.unlock()   // 減衰ループを止めてから戻す（競合防止）
    kb.brightness = savedBrightness
    kb.setAuto(true)
    print("\nrestored.")
    exit(0)
}

// 減衰ループ（別スレッド）: 25ms ごとに glow を少し減らして反映
DispatchQueue.global().async {
    while true {
        lock.lock(); let done = stopped; glow *= 0.82; let g = glow; lock.unlock()
        if done { break }
        kb.brightness = g       // 減衰率 0.82: 1 に近いほど余韻が長い
        usleep(25_000)
    }
}

// 端末を raw モードにして 1 キーずつ受け取る（tty のときだけ）
var original = termios()
let isTTY = isatty(STDIN_FILENO) != 0
if isTTY {
    tcgetattr(STDIN_FILENO, &original)
    var raw = original
    raw.c_lflag &= ~UInt(ECHO | ICANON | ISIG)   // エコー/行バッファ/Ctrl-C割込 を無効 = 1打鍵ずつ受ける
    tcsetattr(STDIN_FILENO, TCSANOW, &raw)
}
defer { if isTTY { tcsetattr(STDIN_FILENO, TCSANOW, &original) } }

print("⌨️  Type to glow — 打鍵するたびキーボードが光る。'q' か Ctrl-C で終了")

// 1 バイトずつ読む。打鍵 → glow を跳ね上げる。
var byte: UInt8 = 0
while read(STDIN_FILENO, &byte, 1) == 1 {
    if byte == UInt8(ascii: "q") || byte == 3 { break }   // q / Ctrl-C
    lock.lock(); glow = min(1.0, glow + 0.9); lock.unlock()
}

restoreAndExit()
