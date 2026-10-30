# LZString-Swift

[![Build](https://github.com/takagi-denki/lzstring-swift/actions/workflows/build.yml/badge.svg)](https://github.com/takagi-denki/lzstring-swift/actions/workflows/build.yml)
[![Test](https://github.com/takagi-denki/lzstring-swift/actions/workflows/test.yml/badge.svg)](https://github.com/takagi-denki/lzstring-swift/actions/workflows/test.yml)
[![codecov](https://codecov.io/github/takagi-denki/lzstring-swift/graph/badge.svg)](https://codecov.io/github/takagi-denki/lzstring-swift)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE.txt)

[English](README.md) | **日本語**

pieroxy 氏による LZW ベースの文字列圧縮ライブラリ [lz-string](https://github.com/pieroxy/lz-string) の Swift 移植版です。

圧縮結果は本家 JavaScript 実装とバイト単位で一致します。Swift で圧縮したデータをブラウザで展開することも、その逆も可能です。ただし言語をまたぐ前に 2 点だけ注意が必要です。`Data` 形式は JavaScript の `Uint8Array` と**バイト順が逆**で、非推奨の生 `String` 形式は不可逆です。[JavaScript との相互運用](#javascript-との相互運用)を参照してください。

## 特徴

- **本家 JavaScript 版と互換。** 全形式の出力を `lz-string` とバイト単位で照合しています。そのうち 4 形式は JavaScript と直接交換でき、`Data` はバイト順の入れ替えが必要です。
- **6 つの出力形式** — Base64、URL セーフ、UTF-16、`[UInt8]`、`Data`、生の `String`（非推奨）。
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
    .package(url: "https://github.com/takagi-denki/lzstring-swift.git", from: "1.2.0"),
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
| `compressToUInt8Array` / `decompressFromUInt8Array` | `[UInt8]`、ビッグエンディアン | 220 バイト (39%) | JavaScript の `Uint8Array` に渡すとき |
| `compress` / `decompress` | `Data`、リトルエンディアン | 220 バイト (39%) | **最小。** ファイル・ソケット・DB に書くとき。そのままでは JavaScript と交換できません（[バイト順の注意](#data-はバイト順の入れ替えが必要)） |
| `compress` / `decompress` | `String` | — | ⚠️ **非推奨** — Swift では不可逆、[注意点](#注意点)を参照 |

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

この 2 つは同じ 16 ビットストリームを**逆のバイト順**で持ちます。`Data` がリトルエンディアン、`[UInt8]` がビッグエンディアンです。Swift の中だけで使う限り問題になりません。各形式は対応する展開関数とだけ組み合わせるためです。問題になるのはバイト列を JavaScript へ渡すときで、[`Data` はバイト順の入れ替えが必要](#data-はバイト順の入れ替えが必要)を参照してください。

## JavaScript との相互運用

次の 4 形式は変換なしで `lz-string` と直接交換できます。

- `compressToBase64` / `decompressFromBase64`
- `compressToEncodedURIComponent` / `decompressFromEncodedURIComponent`
- `compressToUTF16` / `decompressFromUTF16`
- `compressToUInt8Array` / `decompressFromUInt8Array`（JavaScript の `compressToUint8Array` / `decompressFromUint8Array` と対応）

残る 2 形式は交換用ではありません。`Data` は後述のバイト順の入れ替えが必要で、非推奨の生 `String` 形式は Swift では不可逆です（[注意点](#生の-string-形式は非推奨)）。

相互運用できる範囲は Swift の `String` が表現できるテキストに限られます。JavaScript の文字列は孤立サロゲートを保持できますが Swift の `String` は保持できないため、そうしたテキストは形式に関わらず往復できません。

Swift で圧縮して…

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

空文字列も本家と同じく、**空でない**圧縮結果になります。`compressToBase64("")` は `""` ではなく `"Q==="` です。1.2.0 より前のリリースは空文字列を返していたため、空入力の圧縮結果はバージョン間で異なります。どちらの形式も展開すれば `""` に戻ります。

### `Data` はバイト順の入れ替えが必要

`compress(input:) -> Data` は 16 ビット単位を**リトルエンディアン**で格納します。`compressToUInt8Array` と JavaScript の `compressToUint8Array` は**ビッグエンディアン**です。`Data(_:)` や `[UInt8](_:)` による型変換はバイトをコピーするだけで並べ替えません。そのため `Data` をそのまま JavaScript に渡すと別のデータとして読まれ、しかも**無音で失敗します**。エラーにはならず、空文字列か無意味な文字列が返ります。

```javascript
// `LZString.compress(input: "Hello, World!") as Data` のバイト列
LZString.decompressFromUint8Array(new Uint8Array([133, 4, 54, 48, 246, 96, 64, 3, 14, 4, 1, 169, 128, 57, 4, 38, 0, 34]))
// "ࠨࠨࠨࠨࠨᦼ…" — エラーではない
```

渡し先が JavaScript なら `compressToUInt8Array` を使うのが最も簡単です。すでに `Data` を持っている場合は 2 バイトずつ入れ替えてください。

```swift
let data: Data = LZString.compress(input: text)
var forJavaScript = [UInt8]()
forJavaScript.reserveCapacity(data.count)
for index in stride(from: data.startIndex, to: data.endIndex, by: 2) {
    forJavaScript.append(data[index + 1])
    forJavaScript.append(data[index])
}
```

逆方向も同じです。`Data` を受け取る `decompress(input:)` は、2 バイトずつ入れ替えない限り JavaScript の `Uint8Array` を読めません。

## 注意点

### 生の `String` 形式は非推奨

`compress(input:) -> String` と `decompress(input: String)` は 1.1.0 で `@available(*, deprecated)` になりました。動作自体は変わらず、既存コードもビルドが通ります（警告が出るだけです）。

この形式は**往復できません**。生の 16 ビットストリームには対になっていないサロゲートコードユニットが現れることがありますが、Swift の `String` は常に妥当な Unicode テキストであることが保証される型のため、これを保持できず `U+FFFD` に置換されてデータが壊れます。これは型の性質であり、修正可能な不具合ではありません。JavaScript の文字列は UTF-16 コードユニットの列なので孤立サロゲートを保持できますが、Swift の `String` にはできません。

可逆性が必要な場合は `Data`、`[UInt8]`、`compressToUTF16` を使ってください。[#22](https://github.com/takagi-denki/lzstring-swift/issues/22) を参照。

### 不正な入力でもエラーにはならない

展開処理はクラッシュしませんが、**入力の検証にはなりません**。正しい圧縮データでない入力に対しては、空文字列か無意味な文字列を返します。

```swift
LZString.decompressFromBase64(input: "A")         // ""
LZString.decompressFromBase64(input: "not-valid") // "둞è둞è둞è"
```

この 2 例はたまたま本家 JavaScript 実装と一致しますが、**不正な入力の挙動が一致する保証はありません**。このライブラリが約束するバイト単位の互換性は、完全で妥当なペイロードについてのものです。

**切り詰められた**ペイロードに対しては、意図的に本家より厳格です。入力を読み切った時点で停止します。一方 JavaScript は入力末尾を越えた読み取りをゼロビットとして扱うため、そのまま復号できてしまう場合があります（[#21](https://github.com/takagi-denki/lzstring-swift/issues/21)）。

```swift
LZString.decompressFromBase64(input: "IZ") // ""
```

```javascript
LZString.decompressFromBase64("IZ") // "a"
```

この種の差異はすべて `Tests/LZStringTests/MalformedInputTests.swift` に名前付きで固定してあるため、偶然そうなっているものはありません。ほかに既知の差異として、空入力の戻り値（JavaScript は `null`、Swift は戻り値型が非オプショナルなため `""`）と、奇数長の `[UInt8]` の扱い（JavaScript は例外を投げ、このライブラリは投げません）があります。

空文字列という戻り値はそれ自体では曖昧です。空のテキストを正しく展開した結果でもあり、失敗した結果でもあるため、戻り値だけでは区別できません。

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

[MIT](LICENSE.txt) — 本 Swift 移植版は、移植元の [lz-string](https://github.com/pieroxy/lz-string) と同じく MIT ライセンスで配布しています。移植元の著作権表示は [LICENSE.txt](LICENSE.txt) に保持しています。

1.1.0 までのリリースは WTFPL で配布していました。その許諾を取り消すものではなく、本変更は以降の配布に適用されます。
