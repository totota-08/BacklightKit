<div align="center">

# BacklightKit ⌨️💡

**Mac の内蔵キーボードバックライトを、Swift（`BacklightKit`）からもシェル（`backlit`）からも読み書きする。**

[![CI](https://github.com/totota-08/BacklightKit/actions/workflows/ci.yml/badge.svg)](https://github.com/totota-08/BacklightKit/actions/workflows/ci.yml)
[![Release](https://github.com/totota-08/BacklightKit/actions/workflows/release.yml/badge.svg)](https://github.com/totota-08/BacklightKit/actions/workflows/release.yml)
[![Platform](https://img.shields.io/badge/platform-macOS%2012%2B-lightgrey.svg)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

[English](README.md) · [日本語](README.ja.md)

</div>

---

macOS はキーボードバックライトの公開 API を一度も用意していません。**BacklightKit** は Apple の
**非公開** `CoreBrightness` フレームワークを小さなライブラリに包み、明るさの読み書き、実際の
光量（nits）の取得、点滅エフェクトのスクリプト化を可能にします。しかも
**`sudo` 不要・entitlements 不要・SIP 変更も不要**。

依存ゼロ。バイナリ 1 つ。バックライト付きキーボードを持つ Apple Silicon / Intel Mac で動作します。

```console
$ backlit info
keyboard 95158913 (built-in)
  brightness       : 0.3610  (0.0–1.0)
  light output     : 5.36 nits
  auto supported   : true
  auto brightness  : true
  idle dim time    : 0.00 s
```

> ⚠️ **非公開 API です。** Objective-C ランタイム経由で Apple の未公開フレームワークを呼びます。
> 特権は不要で安全に劣化しますが、macOS のアップデートで変更・削除される可能性があります。
> [仕組み](#仕組み) と [動作確認済み](#動作確認済み) を参照。

## 目次

- [インストール](#インストール)
- [CLI コマンド一覧](#cli-コマンド一覧)
- [ライブラリ](#ライブラリ)
- [サンプル](#サンプル)
- [仕組み](#仕組み)
- [動作確認済み](#動作確認済み)
- [よくある質問](#よくある質問)
- [コントリビュート](#コントリビュート)
- [ライセンス](#ライセンス)

## インストール

### Homebrew

```sh
brew install totota-08/tap/backlit
```

### Swift Package Manager（ライブラリ）

```swift
dependencies: [
    .package(url: "https://github.com/totota-08/BacklightKit", from: "0.3.0")
]
```
```swift
.target(name: "YourApp", dependencies: [
    .product(name: "BacklightKit", package: "BacklightKit")
])
```

### ソースから

```sh
git clone https://github.com/totota-08/BacklightKit
cd BacklightKit
make install          # release ビルドして /usr/local/bin に配置
```

各 [リリース](https://github.com/totota-08/BacklightKit/releases) にビルド済みバイナリが添付されます。

## CLI コマンド一覧

いつでも `backlit help`。各コマンドは既定で内蔵キーボードを対象にします。`--keyboard <id>`
（idは `backlit info` で確認）で別のキーボードを指定できます。`fade` / `pulse` / `morse` は
`Ctrl-C` / `SIGTERM` で元の状態に復元します。

### `info`
バックライト対応キーボードすべての状態を表示。

```sh
backlit info            # 人が読む形式
backlit info --json     # JSON
```

| 項目 | 意味 |
|---|---|
| `brightness` | 現在の明るさ `0.0`–`1.0` |
| `light output` | 実際の光量（**nits**）。非対応なら `n/a` |
| `auto supported` | 環境光センサーを持つか |
| `auto brightness` | 自動調光が ON か |
| `saturated` / `suppressed` / `dimmed` | ライブの状態フラグ（非対応は `n/a`） |
| `idle dim time` | 放置で暗くなるまでの秒数（`0` = 暗くならない） |

### `get`
現在の明るさだけを出力。スクリプト向け。

```sh
backlit get            # -> 0.3610
```

### `set <0..1>`
明るさを設定。`--fade` で即時ではなく滑らかに変化。

```sh
backlit set 0.5
backlit set 1 --fade
```

### `up` / `down` `[step]`
明るさを上げ下げ。刻み幅の既定は `0.1`。

```sh
backlit up             # +0.10
backlit down 0.25      # -0.25
```

### `fade <0..1> [--duration SEC]`
現在値から目標値へ滑らかに変化。既定 `0.6` 秒。

```sh
backlit fade 1.0 --duration 2
```

### `pulse [オプション]`
`Ctrl-C` まで 2 値の間で「呼吸」（終了時に元の状態へ復帰）。エフェクト中は自動調光を切ります。

| オプション | 既定値 | 意味 |
|---|---|---|
| `--min <0..1>` | `0.0` | 下限 |
| `--max <0..1>` | `1.0` | 上限 |
| `--period <秒>` | `1.6` | 1 呼吸あたりの秒数 |
| `--count <n>` | `0` | 呼吸の回数（`0` = 無限） |

```sh
backlit pulse --min 0.1 --max 0.8 --period 2
backlit pulse --count 3
```

### `morse <text> [オプション]`
テキストをモールス信号で点滅。総時間を先に表示し、未対応文字はスキップ、終了時に復元します。

| オプション | 既定値 | 意味 |
|---|---|---|
| `--unit <秒>` | `0.13` | モールス 1 単位（ドット）の長さ |
| `--peak <0..1>` | `1.0` | 点灯フラッシュの明るさ |

```sh
backlit morse SOS
backlit morse "hello world" --unit 0.08 --peak 0.7
```

### `auto <on|off>`
環境光による自動調光を切り替え。

```sh
backlit auto off       # 手動制御
backlit auto on        # システムに戻す
```

### `dim <seconds>`
放置で暗くなるまでの秒数。`0` で無効。

```sh
backlit dim 5
backlit dim 0
```

## ライブラリ

操作する「主語」は `Keyboard` です。`KeyboardBacklight()` がそれらを見つけ、便利アクセサを
デフォルト（内蔵）キーボードへ委譲します。

```swift
import BacklightKit

guard let kb = KeyboardBacklight() else { return }   // 非対応機なら nil
// …失敗の「理由」が必要なら:
// let kb = try KeyboardBacklight.discover()         // DiscoveryError を投げる

// 主語ファースト: キーボードを直接操作。
kb.builtIn?.brightness = 1.0
print(kb.defaultKeyboard.nits ?? -1)                 // 物理的な光量（nits・Double?）

// 便利アクセサ（dynamic member lookup で全プロパティをデフォルトキーボードへ委譲）
kb.brightness = 0.5
print(kb.brightness)

// エラー方針は一本: 書き込みは全て throwing メソッドを持つ。
// プロパティ setter は失敗を無視する fire-and-forget の便宜版。
try kb.setBrightness(1.0, fade: .slow)               // FadeSpeed: .instant / .slow / .fast
try kb.defaultKeyboard.setAutoBrightness(false)
try kb.defaultKeyboard.setIdleDimTime(30)

// スコープ付き手動制御: 輝度+autoを保存し、autoを切り、必ず復元する。
try kb.withManualControl { board in
    for _ in 0..<3 {
        try board.setBrightness(1); usleep(120_000)
        try board.setBrightness(0); usleep(120_000)
    }
}

// async 版ならスレッドをブロックせず Task.sleep が使える。
try await kb.withManualControl { board in
    try board.setBrightness(1)
    try await Task.sleep(nanoseconds: 120_000_000)
    try board.setBrightness(0)
}

// 「非対応」は偽の 0 ではなく nil。
print(kb.isSuppressed ?? false, kb.defaultKeyboard.idleDimTime ?? 0)

// 変更を（ポーリングで）監視する AsyncStream。
Task {
    for await level in kb.defaultKeyboard.brightnessStream() {
        print("brightness →", level)
    }
}

// デフォルト以外も含め全キーボード。Keyboard は Identifiable + Hashable なので
// SwiftUI の ForEach にそのまま渡せる。
for keyboard in kb.keyboards {
    print(keyboard.id, keyboard.isBuiltIn, keyboard.brightness)
}
```

**`Keyboard`** — `brightness`（get/set・`Double`）, `setBrightness(_:fade:) throws`,
`nits: Double?`, `autoBrightness`, `setAutoBrightness(_:) throws`, `supportsAutoBrightness`,
`isSaturated/isSuppressed/isDimmed: Bool?`, `idleDimTime: TimeInterval?`（読み取り専用）,
`setIdleDimTime(_:) throws`, `disableIdleDim() throws`, `withManualControl { }`（sync + async）,
`brightnessStream(pollInterval:)`, `isBuiltIn`。`Identifiable`・`Hashable`・`Sendable`。

**`KeyboardBacklight`** — `keyboards`, `defaultKeyboard`, `builtIn`, `discover() throws`
（`DiscoveryError` で理由つき失敗）、加えて `Keyboard` 全プロパティの dynamic member 委譲。
型は一貫して `Double`/`TimeInterval`、非対応の読み取りは `Optional`。

## サンプル

SPM で実行できます。`import BacklightKit` しているのでコピペ不要:

```sh
swift run example-morse "HELLO WORLD" --unit 0.1   # フレーズをモールスで点滅
swift run example-typeglow                         # 打鍵で光る。'q' で終了
```

ソースは [`examples/`](examples)。

## 仕組み

内蔵キーボードのバックライトは PWM 駆動の白色導光板が 1 枚あるだけで、Apple Silicon では
IORegistry に `kbd-backlight` という `AppleARMPWMDevice` として現れます。ユーザー空間からは
`CoreBrightness.framework` 内の非公開クラス `KeyboardBrightnessClient` 経由で制御します。

`backlit` はそのフレームワークを `dlopen` し、Objective-C ランタイム越しに呼ぶため、
**ビルド時に非公開シンボルへ一切リンクしません**。起動時に `responds(to:)` で機能を判定するので、
「非対応」は `nil` として表面化し、コアのセレクタが無い機種では `KeyboardBacklight()` が `nil` を
返します —— クラッシュも偽のゼロもありません。

## 動作確認済み

| Mac | チップ | macOS | 状態 |
|---|---|---|---|
| MacBook Air (2020) | Apple M1 | 26.x | ✅ 読み書き / nits / auto / idle-dim |

他の機種で試したら、モデル名と `sw_vers` のビルドを添えて行を追加する PR を歓迎します。
補足: 内蔵キーボードは白色ゾーンが **1 つ**（キー個別/RGB 不可）、`idleDimTime = 0` は
アイドル減光 **無効** を意味します。

## よくある質問

**ゲーミングキーボードみたいにキー個別／RGB を光らせられる？**
できません。内蔵キーボードは明るさチャンネル 1 本の単一白色ゾーンで、キー個別のアドレスも色も
ハードに存在しません。ソフトの制限ではなく物理的な制約です。

**`sudo` や SIP 無効化は必要？**
不要です。通常ユーザーで動きます。

**アップデートで壊れる？**
可能性はあります（非公開 API のため）。各呼び出しは防御的で表面積も小さいので、セレクタが
変わっても修正は容易です。回帰したら macOS ビルドを添えて issue をどうぞ。

**サンドボックスで使える？**
使えません。CLI やメニューバー／エージェント用途向けで、App Store アプリには不向きです。

## コントリビュート

Issue / PR 歓迎。CI が全 PR を macOS でビルド＆テストし、`Sources/backlit/main.swift` の
バージョンが `main` で変わると自動でリリースされます。最初の一歩に良いもの: 動作確認済み機種の
追加、CLI エフェクトの追加、Intel / Touch Bar 機での挙動確認。

## ライセンス

[MIT](LICENSE) © totota-08

> ランタイム経由で Apple の非公開フレームワークを利用しています。Apple とは無関係で、承認も受けていません。
