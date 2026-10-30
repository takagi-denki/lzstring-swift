# LZString-Swift

[![Build](https://github.com/takagi-denki/lzstring-swift/actions/workflows/build.yml/badge.svg)](https://github.com/takagi-denki/lzstring-swift/actions/workflows/build.yml)
[![Test](https://github.com/takagi-denki/lzstring-swift/actions/workflows/test.yml/badge.svg)](https://github.com/takagi-denki/lzstring-swift/actions/workflows/test.yml)
[![codecov](https://codecov.io/github/takagi-denki/lzstring-swift/graph/badge.svg)](https://codecov.io/github/takagi-denki/lzstring-swift)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE.txt)

**English** | [日本語](README.ja.md)

A Swift port of [lz-string](https://github.com/pieroxy/lz-string), the LZW-based string compressor by pieroxy.

The compressed output matches the original JavaScript implementation byte for byte, so a payload produced in Swift can be decompressed in a browser and vice versa. Two details need care before you cross that boundary: the `Data` format uses the **opposite byte order** from a JavaScript `Uint8Array`, and the deprecated raw `String` format is lossy. See [Interoperating with JavaScript](#interoperating-with-javascript).

## Features

- **Compatible with the JavaScript original.** Every format's output is checked against `lz-string` byte for byte. Four of them are exchanged with JavaScript directly; `Data` needs its byte order swapped first.
- **Six output formats** — Base64, URL-safe, UTF-16, `[UInt8]`, `Data`, and raw `String` (deprecated).
- **Low allocation.** Compressing allocates about 2% of what 1.2.0 did, and decompressing about half, for byte-identical output. See [Performance](#performance).
- **No third-party dependencies.** The library target imports only `Foundation`.
- **Runs everywhere Swift does.** CI builds on macOS, Linux, Windows, and the static Linux musl SDK.

## Requirements

| | |
| --- | --- |
| Swift | 6.2 or later |
| Apple platforms | macOS 13+, iOS 13+, tvOS 13+, watchOS 6+ |
| Other platforms | Linux, Windows, static Linux (musl) |

## Installation

### Swift Package Manager

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/takagi-denki/lzstring-swift.git", from: "1.3.0"),
]
```

Then add it to your target:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "LZString", package: "lzstring-swift"),
    ]
)
```

### Xcode

**File → Add Package Dependencies…** and enter `https://github.com/takagi-denki/lzstring-swift.git`.

## Usage

```swift
import LZString

let compressed = LZString.compressToBase64(input: "Hello, World!")
// "BIUwNmD2A0AEDqkBOYAmBCIA"

let original = LZString.decompressFromBase64(input: compressed)
// "Hello, World!"
```

### Choosing a format

Sizes below are for a 570-byte ASCII sample (`"Lorem ipsum dolor sit amet, consectetur adipiscing elit. "` repeated ten times).

| Format | Output | Size | Use it when |
| --- | --- | --- | --- |
| `compressToBase64` / `decompressFromBase64` | `String` (`A–Z a–z 0–9 + / =`) | 292 chars (51%) | You need plain text that survives anything |
| `compressToEncodedURIComponent` / `decompressFromEncodedURIComponent` | `String` (`A–Z a–z 0–9 + - $`) | 292 chars (51%) | The value goes in a URL or query string |
| `compressToUTF16` / `decompressFromUTF16` | `String` (15 bits per character) | 118 chars (236 bytes as UTF-16) | You store into a UTF-16 store such as `localStorage` |
| `compressToUInt8Array` / `decompressFromUInt8Array` | `[UInt8]`, big-endian | 220 bytes (39%) | You hand the bytes to a JavaScript `Uint8Array` |
| `compress` / `decompress` | `Data`, little-endian | 220 bytes (39%) | **Most compact.** Writing to a file, a socket, or a database. Not interchangeable with JavaScript as-is — see [the byte-order note](#data-needs-its-byte-order-swapped) |
| `compress` / `decompress` | `String` | — | ⚠️ **Deprecated** — lossy in Swift, see [Caveats](#caveats) |

### Base64

```swift
let compressed = LZString.compressToBase64(input: text)
let original = LZString.decompressFromBase64(input: compressed)
```

### URL-safe

Produces no `/` and no `=` padding, so it can be dropped straight into a query string.
The alphabet does still contain `+`, which some URL decoders turn back into a space — `decompressFromEncodedURIComponent` accounts for that and converts it back.

```swift
let compressed = LZString.compressToEncodedURIComponent(input: text)
let original = LZString.decompressFromEncodedURIComponent(input: compressed)
```

### UTF-16

Packs 15 bits into each character — the most compact option when the destination counts characters rather than bytes.

```swift
let compressed = LZString.compressToUTF16(input: text)
let original = LZString.decompressFromUTF16(input: compressed)
```

### Bytes

`compress(input:)` is overloaded on its return type, so the call site **must** state which one it wants:

```swift
let data: Data = LZString.compress(input: text)
let original = LZString.decompress(input: data)

let bytes: [UInt8] = LZString.compressToUInt8Array(input: text)
let sameAgain = LZString.decompressFromUInt8Array(input: bytes)
```

Without the annotation the compiler cannot pick an overload:

```swift
let data = LZString.compress(input: text)        // ❌ ambiguous
let data = LZString.compress(input: text) as Data // ✅
```

The two carry the same 16-bit stream in **opposite byte orders**: `Data` is little-endian, `[UInt8]` is big-endian. Within Swift this never matters, because each format decompresses with its own counterpart. It matters as soon as the bytes leave for JavaScript — see [`Data` needs its byte order swapped](#data-needs-its-byte-order-swapped).

## Performance

1.3.0 is a performance release. **The compressed bytes did not change**, so a payload written by 1.2.0 still decompresses here and vice versa; nothing stored by an older version needs migrating.

Allocation counts are deterministic, so these are reproducible anywhere (`swift package benchmark`, `mallocCountTotal` p50, the 445-unit Latin paragraph the benchmarks use):

| | 1.2.0 | 1.3.0 |
| --- | ---: | ---: |
| `compressToBase64` | 907 | 18 |
| `compress` returning `Data` | 1061 | 19 |
| `compressToUInt8Array` | 1062 | 17 |
| `decompressFromBase64` | 624 | 329 |

Throughput depends on the machine, so treat the rest as an indication rather than a figure to rely on. On an Apple-silicon macOS build, throughput p50 roughly doubled on the mid-sized benchmarks and rose about sixfold on 64 Ki units of a repeating pattern, because the compressor no longer copies a growing phrase for every code unit. A short 11-character payload gained about 4%: there is little per-unit work to remove at that size. Measure your own workload with `swift package benchmark`.

## Interoperating with JavaScript

Four formats are exchanged with `lz-string` directly, with no conversion:

- `compressToBase64` / `decompressFromBase64`
- `compressToEncodedURIComponent` / `decompressFromEncodedURIComponent`
- `compressToUTF16` / `decompressFromUTF16`
- `compressToUInt8Array` / `decompressFromUInt8Array`, against the JavaScript `compressToUint8Array` / `decompressFromUint8Array`

The other two are not interchange formats. `Data` needs its byte order swapped, as described below, and the deprecated raw `String` format is lossy in Swift — see [Caveats](#the-raw-string-format-is-deprecated).

Interoperability is also limited to text a Swift `String` can hold. A JavaScript string may contain an unpaired surrogate; a Swift `String` cannot, so such text is not round-trippable regardless of the format.

Compress in Swift:

```swift
LZString.compressToEncodedURIComponent(input: "Hello, World!")
// "BIUwNmD2A0AEDqkBOYAmBCIA"
```

…and decompress in JavaScript:

```javascript
LZString.decompressFromEncodedURIComponent("BIUwNmD2A0AEDqkBOYAmBCIA")
// "Hello, World!"
```

The reverse works too — pass a string produced by `lz-string` to the matching `decompressFrom…` function.

An empty string compresses to a *non-empty* payload, exactly as in the original: `compressToBase64("")` is `"Q==="`, not `""`. Releases before 1.2.0 returned an empty string here, so compressed output of an empty input differs between those versions. Decompressing either form still yields `""`. No release since has changed any output: 1.3.0 is byte-compatible with 1.2.0 in both directions.

### `Data` needs its byte order swapped

`compress(input:) -> Data` stores each 16-bit unit **little-endian**. `compressToUInt8Array` and the JavaScript `compressToUint8Array` store it **big-endian**. Converting the type with `Data(_:)` or `[UInt8](_:)` copies the bytes without reordering them, so a `Data` payload handed to JavaScript is read as different data — and it **fails silently**, returning an empty string or meaningless text rather than reporting an error:

```javascript
// The bytes of `LZString.compress(input: "Hello, World!") as Data`
LZString.decompressFromUint8Array(new Uint8Array([133, 4, 54, 48, 246, 96, 64, 3, 14, 4, 1, 169, 128, 57, 4, 38, 0, 34]))
// "ࠨࠨࠨࠨࠨᦼ…" — not an error
```

The simplest fix is to use `compressToUInt8Array` whenever the destination is JavaScript. If you already have a `Data`, swap each pair of bytes:

```swift
let data: Data = LZString.compress(input: text)
var forJavaScript = [UInt8]()
forJavaScript.reserveCapacity(data.count)
for index in stride(from: data.startIndex, to: data.endIndex, by: 2) {
    forJavaScript.append(data[index + 1])
    forJavaScript.append(data[index])
}
```

The same applies in reverse: `decompress(input:)` taking `Data` does not read a JavaScript `Uint8Array` until the pairs are swapped.

## Caveats

### The raw `String` format is deprecated

`compress(input:) -> String` and `decompress(input: String)` are marked `@available(*, deprecated)` as of 1.1.0. They still work and existing code still builds — you will just get a warning.

They are **not** round-trip safe. The raw 16-bit stream can contain unpaired surrogate code units, and a Swift `String` is guaranteed to be valid Unicode text, so it cannot hold them; they are replaced with `U+FFFD` and the data is destroyed. This is a property of the type, not a bug that can be fixed — a JavaScript string is a sequence of UTF-16 code units and can hold a lone surrogate, but a Swift `String` cannot.

Use `Data`, `[UInt8]`, or `compressToUTF16` when you need a lossless result. See [#22](https://github.com/takagi-denki/lzstring-swift/issues/22).

### Malformed input does not throw

Decompression never traps, but it is **not** a validity check. Given input that is not valid compressed data, it returns either an empty string or a meaningless one:

```swift
LZString.decompressFromBase64(input: "A")         // ""
LZString.decompressFromBase64(input: "not-valid") // "둞è둞è둞è"
```

Those two happen to agree with the original JavaScript implementation, but **malformed input is not guaranteed to behave identically**. The byte-for-byte compatibility this library promises is about complete, valid payloads.

On a **truncated** payload this library is deliberately stricter. It stops as soon as the input is exhausted, while JavaScript treats reads past the end as zero bits and can sometimes still finish ([#21](https://github.com/takagi-denki/lzstring-swift/issues/21)):

```swift
LZString.decompressFromBase64(input: "IZ") // ""
```

```javascript
LZString.decompressFromBase64("IZ") // "a"
```

Every such difference is pinned by name in `Tests/LZStringTests/MalformedInputTests.swift`, so none of them is accidental. Other known differences are the return value for empty input (JavaScript `null`, Swift `""`, because the Swift return type is non-optional) and the handling of an odd-length `[UInt8]`, which JavaScript throws on and this library does not.

An empty return value is ambiguous on its own: it is what a successful decode of empty text produces as well as what a failure produces, so you cannot use it to tell the two apart.

Verify your data separately if it comes from an untrusted source.

### This is not a general-purpose compressor

lz-string targets short strings held in memory — `localStorage` values, query parameters, cache keys. For files or large payloads, a general-purpose algorithm will beat it comfortably.

## Development

```sh
swift build --target LZString   # build the library
swift test                      # run the test suite
swift package benchmark         # run benchmarks (requires jemalloc)
```

`swift test` must be run from the package root: the tests read their fixtures through paths relative to the working directory.

The fixtures under `Tests/Resources/` are golden output from the JavaScript implementation. If a test fails, the implementation has regressed — do not regenerate the fixtures.

See [AGENTS.md](AGENTS.md) for the full contributor notes.

## Credits

- Original JavaScript implementation: [pieroxy/lz-string](https://github.com/pieroxy/lz-string)

## License

[MIT](LICENSE.txt) — this Swift port is distributed under the MIT License, as is the original [lz-string](https://github.com/pieroxy/lz-string). The upstream copyright notice is preserved in [LICENSE.txt](LICENSE.txt).

Releases up to and including 1.1.0 were distributed under the WTFPL. That grant is not revoked; this change applies to subsequent distributions.
