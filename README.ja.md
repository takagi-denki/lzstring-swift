# LZString-Swift

[![Build](https://github.com/takagi-denki/lzstring-swift/actions/workflows/build.yml/badge.svg)](https://github.com/takagi-denki/lzstring-swift/actions/workflows/build.yml)
[![Test](https://github.com/takagi-denki/lzstring-swift/actions/workflows/test.yml/badge.svg)](https://github.com/takagi-denki/lzstring-swift/actions/workflows/test.yml)
[![codecov](https://codecov.io/github/takagi-denki/lzstring-swift/graph/badge.svg)](https://codecov.io/github/takagi-denki/lzstring-swift)
[![License](https://img.shields.io/badge/License-WTFPL-lightgrey.svg)](http://www.wtfpl.net/)

[English](README.md) | **日本語**

pieroxy 氏による LZW ベースの文字列圧縮ライブラリ [lz-string](https://github.com/pieroxy/lz-string) の Swift 移植版です。

出力は本家 JavaScript 実装とバイト単位で一致します。Swift で圧縮した文字列をブラウザで展開することも、その逆も可能です。

## 特徴

- **本家 JavaScript 版と互換。** 全形式について `lz-string` との一致を検証しています。
- **6 つの出力形式** — Base64、URL セーフ、UTF-16、`[UInt8]`、`Data`、生の `String`。
- **サードパーティ依存なし。** ライブラリターゲットが import するのは `Foundation` のみです。
- **Swift が動く環境で動く。** CI は macOS / Linux / Windows / static Linux (musl) でビルドしています。

## 動作環境

| | |
| --- | --- |
| Swift | 6.2 以降 |
| Apple プラットフォーム | macOS 13+、iOS 13+、tvOS 13+、watchOS 6+ |
| その他 | Linux、Windows、static Linux (musl) |

## インストール

### Swift Package Manager

`Package.swift` に依存を追加します。

```swift
dependencies: [
    .package(url: "https://github.com/takagi-denki/lzstring-swift.git", from: "1.0.0"),
]
```

ターゲットに追加します。

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "LZString", package: "lzstring-swift"),
    ]
)
```

### Xcode

**File → Add Package Dependencies…** から `https://github.com/takagi-denki/lzstring-swift.git` を入力してください。

## 使い方

```swift
import LZString

let compressed = LZString.compressToBase64(input: "Hello, World!")
// "BIUwNmD2A0AEDqkBOYAmBCIA"

let original = LZString.decompressFromBase64(input: compressed)
// "Hello, World!"
```

### 形式の選び方

以下のサイズは 570 バイトの ASCII 文字列（`"Lorem ipsum dolor sit amet, consectetur adipiscing elit. "` を 10 回繰り返したもの）での実測値です。

| 形式 | 出力 | サイズ | 向いている用途 |
| --- | --- | --- | --- |
| `compressToBase64` / `decompressFromBase64` | `String`（`A–Z a–z 0–9 + / =`） | 292 文字 (51%) | どこを通しても壊れないテキストが欲しいとき |
| `compressToEncodedURIComponent` / `decompressFromEncodedURIComponent` | `String`（`A–Z a–z 0–9 + - $`） | 292 文字 (51%) | URL やクエリ文字列に載せるとき |
| `compressToUTF16` / `decompressFromUTF16` | `String`（1 文字 15 ビット） | 118 文字（UTF-16 で 236 バイト） | `localStorage` など UTF-16 で保存する先に入れるとき |
| `compressToUInt8Array` / `decompressFromUInt8Array` | `[UInt8]` | 220 バイト (39%) | JavaScript の `Uint8Array` に渡すとき |
| `compress` / `decompress` | `Data` | 220 バイト (39%) | **最小。** ファイル・ソケット・DB に書くとき |
| `compress` / `decompress` | `String` | — | ⚠️ Swift では不可逆 — [注意点](#注意点)を参照 |

### Base64

```swift
let compressed = LZString.compressToBase64(input: text)
let original = LZString.decompressFromBase64(input: compressed)
```

### URL セーフ

`/` とパディングの `=` を含まないため、クエリ文字列にそのまま載せられます。
ただしアルファベットには `+` が含まれます。URL デコーダによっては空白に変換されますが、`decompressFromEncodedURIComponent` はそれを考慮して元に戻します。

```swift
let compressed = LZString.compressToEncodedURIComponent(input: text)
let original = LZString.decompressFromEncodedURIComponent(input: compressed)
```

### UTF-16

1 文字あたり 15 ビットを詰めます。保存先がバイト数ではなく文字数で数える場合に最も小さくなります。

```swift
let compressed = LZString.compressToUTF16(input: text)
let original = LZString.decompressFromUTF16(input: compressed)
```

### バイト列

`compress(input:)` は戻り値の型だけが異なるオーバーロードです。呼び出し側で型を**明示する必要があります**。

```swift
let data: Data = LZString.compress(input: text)
let original = LZString.decompress(input: data)

let bytes: [UInt8] = LZString.compressToUInt8Array(input: text)
let sameAgain = LZString.decompressFromUInt8Array(input: bytes)
```

型注釈がないとオーバーロードを解決できません。

```swift
let data = LZString.compress(input: text)        // ❌ 曖昧
let data = LZString.compress(input: text) as Data // ✅
```

## JavaScript との相互運用

全形式が本家実装と相互に往復できます。Swift で圧縮して…

```swift
LZString.compressToEncodedURIComponent(input: "Hello, World!")
// "BIUwNmD2A0AEDqkBOYAmBCIA"
```

…JavaScript で展開できます。

```javascript
LZString.decompressFromEncodedURIComponent("BIUwNmD2A0AEDqkBOYAmBCIA")
// "Hello, World!"
```

逆方向も同様です。`lz-string` が生成した文字列を、対応する `decompressFrom…` に渡してください。

## 注意点

### 生の `String` 形式は不可逆

`compress(input:) -> String` と `decompress(input: String)` は**往復できません**。生の 16 ビットストリームには対になっていないサロゲートコードユニットが現れることがあり、Swift の `String` はこれを表現できないため `U+FFFD` に置換されてデータが壊れます。

可逆性が必要な場合は `Data`、`[UInt8]`、`compressToUTF16` を使ってください。[#22](https://github.com/takagi-denki/lzstring-swift/issues/22) を参照。

### 不正な入力でもエラーにはならない

展開処理はクラッシュしませんが、**入力の検証にはなりません**。正しい圧縮データでない入力に対しては、空文字列か無意味な文字列を返します。これは本家 JavaScript 実装とまったく同じ挙動です。

```swift
LZString.decompressFromBase64(input: "A")         // ""
LZString.decompressFromBase64(input: "not-valid") // "둞è둞è둞è"
```

信頼できない入力を扱う場合は、別途検証してください。

### 汎用の圧縮ライブラリではない

lz-string が想定しているのは、メモリ上の短い文字列 — `localStorage` の値、クエリパラメータ、キャッシュキーなどです。ファイルや大きなデータには汎用の圧縮アルゴリズムのほうが明確に有利です。

## 開発

```sh
swift build --target LZString   # ライブラリのビルド
swift test                      # テストの実行
swift package benchmark         # ベンチマーク（jemalloc が必要）
```

`swift test` は**パッケージルートから実行してください**。テストはカレントディレクトリからの相対パスでフィクスチャを読み込みます。

`Tests/Resources/` 以下のフィクスチャは JavaScript 実装が生成したゴールデンファイルです。テストが落ちた場合は実装側のリグレッションなので、フィクスチャを作り直さないでください。

詳しい開発メモは [AGENTS.md](AGENTS.md) を参照してください。

## クレジット

- 本家 JavaScript 実装: [pieroxy/lz-string](https://github.com/pieroxy/lz-string)

## ライセンス

[WTFPL](http://www.wtfpl.net/) — [LICENSE.txt](LICENSE.txt) を参照してください。
