import Foundation

//: # ⌨️💡 Keyboard Morse
//: Blink your Mac's **built-in keyboard backlight** to spell a word in Morse code.
//: Change `word` below and re-run. Watch the keyboard, not the screen.

let word = "HELLO WORLD"          // ← 好きな単語に変えて再実行
let unit  = 0.13            // モールスの1単位（秒）。小さいほど速い

// ---------------------------------------------------------------------------
// 内蔵キーボードバックライトのラッパー（private CoreBrightness framework）
// sudo も SIP 変更も不要。非対応機なら init が nil を返す。
// ---------------------------------------------------------------------------
final class KeyboardBacklight {
    private let client: NSObject
    private let id: UInt64

    init?() {
        guard dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW) != nil,
              let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else { return nil }
        client = cls.init()
        let sel = NSSelectorFromString("copyKeyboardBacklightIDs")
        guard let ids = client.perform(sel)?.takeRetainedValue() as? [NSNumber],
              let first = ids.first else { return nil }
        id = first.uint64Value
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

// ---------------------------------------------------------------------------
let morse: [Character: String] = [
    "A": ".-", "B": "-...", "C": "-.-.", "D": "-..", "E": ".", "F": "..-.",
    "G": "--.", "H": "....", "I": "..", "J": ".---", "K": "-.-", "L": ".-..",
    "M": "--", "N": "-.", "O": "---", "P": ".--.", "Q": "--.-", "R": ".-.",
    "S": "...", "T": "-", "U": "..-", "V": "...-", "W": ".--", "X": "-..-",
    "Y": "-.--", "Z": "--..", "0": "-----", "1": ".----", "2": "..---",
    "3": "...--", "4": "....-", "5": ".....", "6": "-....", "7": "--...",
    "8": "---..", "9": "----.",
]

func blinkMorse(_ text: String, on kb: KeyboardBacklight, unit: TimeInterval) {
    let u = useconds_t(unit * 1_000_000)
    let saved = kb.brightness
    kb.setAuto(false)                       // 環境光センサーに邪魔されないよう一時オフ

    func flash(_ duration: useconds_t) {
        kb.brightness = 1.0; usleep(duration)   // 点灯
        kb.brightness = 0.0; usleep(u)          // シンボル間ギャップ（1単位）
    }

    for ch in text.uppercased() {
        guard let code = morse[ch] else { usleep(u * 4); continue }  // 空白 → 語間ギャップ
        print("\(ch)  \(code)")
        for symbol in code { flash(symbol == "-" ? u * 3 : u) }      // ダッシュ=3, ドット=1
        usleep(u * 2)                                                // 文字間ギャップ
    }

    kb.brightness = saved                   // 元の明るさに戻す
    kb.setAuto(true)                        // 自動調光を復帰
}

// ---------------------------------------------------------------------------
if let kb = KeyboardBacklight() {
    print("💡 \"\(word)\" を点滅（現在の輝度 \(String(format: "%.2f", kb.brightness))）")
    blinkMorse(word, on: kb, unit: unit)
    print("done — 元に戻しました")
} else {
    print("このMacにはバックライト付きキーボードが無いか、APIが使えません")
}

//: ## 遊び方
//: - `word` を自分の名前や「SOS」に変えて再実行
//: - `unit` を `0.06` にすると倍速、`0.25` でゆっくり
//: - `flash` の中身をいじれば点灯の明るさ（1.0）も調整可能
