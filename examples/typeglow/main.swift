import Foundation
import MacKeyboardBacklight

// Type-to-glow: the backlight flares on every keystroke and decays when you stop.
//   swift run example-typeglow      ('q' or Ctrl-C to quit)
//
// Uses the library (guards + restore live there). Restore is wired to normal exit,
// to Ctrl-C (raw mode delivers it as a byte), and to atexit as a backstop, so the
// backlight never gets stranded off.

guard let kb = KeyboardBacklight() else {
    FileHandle.standardError.write(Data("no keyboard backlight on this Mac\n".utf8)); exit(1)
}
let board = kb.defaultKeyboard

let savedBrightness = board.brightness
let savedAuto = board.autoBrightness
board.setAutoBrightness(false)

let lock = NSLock()
var glow = 0.0
var stopped = false

func restore() {
    lock.lock(); if stopped { lock.unlock(); return }; stopped = true; lock.unlock()
    try? board.setBrightness(savedBrightness)
    board.setAutoBrightness(savedAuto)
}
atexit { restore() }   // backstop: fires even on unexpected exit paths

// Decay loop: every 25ms, ease `glow` toward 0 and push it to the backlight.
DispatchQueue.global().async {
    while true {
        lock.lock(); let done = stopped; glow *= 0.82; let g = glow; lock.unlock()
        if done { break }
        try? board.setBrightness(g)   // decay 0.82 → higher = longer afterglow
        usleep(25_000)
    }
}

// Raw terminal so we get one keystroke at a time (and Ctrl-C as a byte, not a signal).
var original = termios()
let isTTY = isatty(STDIN_FILENO) != 0
if isTTY {
    tcgetattr(STDIN_FILENO, &original)
    var raw = original
    raw.c_lflag &= ~UInt(ECHO | ICANON | ISIG)
    tcsetattr(STDIN_FILENO, TCSANOW, &raw)
}

print("⌨️  Type to glow — every keystroke lights the keyboard. 'q' or Ctrl-C to quit")

var byte: UInt8 = 0
while read(STDIN_FILENO, &byte, 1) == 1 {
    if byte == UInt8(ascii: "q") || byte == 3 { break }   // q / Ctrl-C
    lock.lock(); glow = min(1.0, glow + 0.9); lock.unlock()
}

if isTTY { tcsetattr(STDIN_FILENO, TCSANOW, &original) }
restore()
print("\nrestored.")
