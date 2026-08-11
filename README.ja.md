<div align="center">

# kbdlight ⌨️💡

**Mac の内蔵キーボードバックライトを、Swift からもシェルからも読み書きする。**

[![Platform](https://img.shields.io/badge/platform-macOS%2012%2B-lightgrey.svg)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)
[![SPM](https://img.shields.io/badge/SwiftPM-compatible-brightgreen.svg)](https://swift.org/package-manager/)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

[English](README.md) · [日本語](README.ja.md)

</div>

---

macOS はキーボードバックライトの公開 API を一度も用意していません。`kbdlight` は Apple の
**非公開** `CoreBrightness` フレームワークを小さなライブラリに包み、明るさの読み取り・設定、
実際の光量（nits）の取得、点滅エフェクトのスクリプト化を可能にします。しかも
**`sudo` 不要・entitlements 不要・SIP の変更も不要**。

依存ゼロ。バイナリ 1 つ。バックライト付きキーボードを持つ Apple Silicon / Intel Mac で動作します。

```console
$ kbdlight info
keyboard 95158913 (built-in)
  brightness       : 0.3610  (0.0–1.0)
  light output     : 5.36 nits
  ambient available: true
  auto brightness  : true
  idle dim time    : 0.0 s
```

## 目次

- [インストール](#インストール)
- [CLI コマンド一覧](#cli-コマンド一覧)
- [ライブラリ](#ライブラリ)
- [サンプル](#サンプル)
- [仕組み](#仕組み)
- [よくある質問](#よくある質問)
- [コントリビュート](#コントリビュート)
- [ライセンス](#ライセンス)

## インストール

**ソースから（推奨）:**

```sh
git clone https://github.com/totota-08/kbdlight
cd kbdlight
make install          # release ビルドして /usr/local/bin にバイナリを配置
```

別の場所に入れたい場合は `make install PREFIX=~/.local`。

**手動ビルド:**

```sh
swift build -c release
cp .build/release/kbdlight /usr/local/bin/
```

## CLI コマンド一覧

いつでも `kbdlight help` で確認できます。各コマンドはデフォルトで内蔵キーボードを対象にします。

### `info`
バックライト対応キーボードすべての状態をまとめて表示します。

```sh
kbdlight info            # 人が読む形式
kbdlight info --json     # スクリプト向け JSON
```

| 項目 | 意味 |
|---|---|
| `brightness` | 現在の明るさ `0.0`–`1.0` |
| `light output` | 実際の光量（**nits**、Apple のキャリブレーション表由来） |
| `ambient available` | 環境光センサーを持つか |
| `auto brightness` | 自動調光が今 ON か |
| `saturated` / `suppressed` / `dimmed` | ライブの状態フラグ |
| `idle dim time` | 放置で暗くなるまでの秒数（`0` = 暗くならない） |

### `get`
現在の明るさを数値だけで出力します。スクリプトで扱いやすい形。

```sh
kbdlight get            # -> 0.3610
```

### `set <0..1>`
明るさを設定します。`--fade` を付けると即時ではなく滑らかに変化します。

```sh
kbdlight set 0.5
kbdlight set 1 --fade
```

### `up` / `down` `[step]`
明るさを上げ下げします。刻み幅のデフォルトは `0.1`。

```sh
kbdlight up             # +0.10
kbdlight down 0.25      # -0.25
```

### `fade <0..1> [--duration SEC]`
現在の明るさから目標値へ滑らかに変化させます。時間のデフォルトは `0.6` 秒。

```sh
kbdlight fade 1.0 --duration 2
```

### `pulse [オプション]`
`Ctrl-C` を押すまで 2 つの明るさの間で「呼吸」させます（終了時に元の状態へ復帰）。
エフェクト中は自動調光を切って、センサーと競合しないようにします。

| オプション | 既定値 | 意味 |
|---|---|---|
| `--min <0..1>` | `0.0` | 下限 |
| `--max <0..1>` | `1.0` | 上限 |
| `--period <秒>` | `1.6` | 1 呼吸あたりの秒数 |
| `--count <n>` | `0` | 呼吸の回数（`0` = 無限） |

```sh
kbdlight pulse --min 0.1 --max 0.8 --period 2
kbdlight pulse --count 3
```

### `auto <on|off>`
環境光による自動調光を切り替えます。

```sh
kbdlight auto off       # 手動制御に切り替え
kbdlight auto on        # システムに戻す
```

### `dim <seconds>`
放置で暗くなるまでの秒数を設定します。`0` で無効。

```sh
kbdlight dim 5
kbdlight dim 0
```

## ライブラリ

`Package.swift` に追加:

```swift
.package(url: "https://github.com/totota-08/kbdlight", from: "0.1.0")
```

```swift
import MacKeyboardBacklight

guard let kb = KeyboardBacklight() else { return }   // 非対応機なら nil

print(kb.brightness)              // 0.0 ... 1.0
print(kb.level)                   // 物理的な光量（nits・読み取り専用）

kb.brightness = 0.5               // 50% にする
kb.setBrightness(1.0, fade: true) // 滑らかに変化

kb.autoBrightness = false         // 環境光センサーの上書きを止める
print(kb.isSuppressed, kb.isDimmed, kb.isSaturated)

kb.idleDimTime = 10               // 10 秒放置で暗く

for keyboard in kb.keyboards {    // 複数キーボード対応
    print(keyboard.id, keyboard.isBuiltIn, kb.brightness(of: keyboard))
}
```

**公開 API:** `keyboards`, `default`, `brightness`, `level`（nits）, `autoBrightness`,
`isSaturated`, `isSuppressed`, `isDimmed`, `idleDimTime`, `setBrightness(_:of:fade:)`,
`setAutoBrightness(_:of:)`, `setIdleDimTime(_:of:)`、および各リーダーのキーボード指定版。

## サンプル

[`examples/`](examples) 内:

- **[`TypeGlow.swift`](examples/TypeGlow.swift)** — 打鍵するたびバックライトがフワッと光り、
  指を止めると暗くなる。タイピングがそのまま光になります。
  ```sh
  swift examples/TypeGlow.swift    # 打ってみる。'q' か Ctrl-C で終了
  ```
- **[`KeyboardMorse.playground`](examples/KeyboardMorse.playground)** — 好きな単語をモールス信号で
  点滅。Xcode で開いて `word` を変えて実行するだけ。

## 仕組み

内蔵キーボードのバックライトは PWM 駆動の白色導光板が 1 枚あるだけで、Apple Silicon では
IORegistry に `kbd-backlight` という `AppleARMPWMDevice` として現れます。ユーザー空間からは
`CoreBrightness.framework` 内の非公開クラス `KeyboardBrightnessClient` 経由で制御します。

`kbdlight` はそのフレームワークを `dlopen` し、Objective-C ランタイム越しにクラスを呼びます。
つまり**ビルド時に非公開シンボルへ一切リンクしない**ため、Apple が名前を変えたり削除しても
`KeyboardBacklight()` が `nil` を返すだけで安全に劣化します。

## よくある質問

**ゲーミングキーボードみたいにキー個別／RGB を光らせられる？**
できません。内蔵キーボードは明るさチャンネル 1 本の単一白色ゾーンで、キー個別のアドレスも色も
ハードに存在しません。ソフトの制限ではなく物理的な制約です。

**`sudo` や SIP 無効化は必要？**
不要です。特別な entitlements もなく、通常ユーザーで動きます。

**アップデートで壊れる？**
可能性はあります（非公開 API のため）。各呼び出しは防御的で安全に劣化し、コードも小さいので
セレクタが変わっても修正は容易です。

**サンドボックスで使える？**
使えません。非公開フレームワークに依存するため、CLI ツールやメニューバー／エージェント用途向けで、
App Store アプリには不向きです。

## コントリビュート

Issue / PR 歓迎です。最初の一歩に良いもの: 対応キーボードの拡充、CLI のエフェクト追加、
各 Mac モデル・macOS バージョンでの挙動確認（PR にモデルと OS ビルドを記載してください）。

## ライセンス

[MIT](LICENSE) © totota-08

> ランタイム経由で Apple の非公開フレームワークを利用しています。Apple とは無関係で、承認も受けていません。
