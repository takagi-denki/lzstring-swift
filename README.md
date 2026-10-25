# LZString-Swift

[![Build](https://github.com/takagi-denki/lzstring-swift/actions/workflows/build.yml/badge.svg)](https://github.com/takagi-denki/lzstring-swift/actions/workflows/build.yml)
[![Test](https://github.com/takagi-denki/lzstring-swift/actions/workflows/test.yml/badge.svg)](https://github.com/takagi-denki/lzstring-swift/actions/workflows/test.yml)
[![codecov](https://codecov.io/github/takagi-denki/lzstring-swift/graph/badge.svg)](https://codecov.io/github/takagi-denki/lzstring-swift)
[![License](https://img.shields.io/badge/License-WTFPL-lightgrey.svg)](http://www.wtfpl.net/)

**English** | [日本語](README.ja.md)

A Swift port of [lz-string](https://github.com/pieroxy/lz-string), the LZW-based string compressor by pieroxy.

The output is byte-for-byte identical to the original JavaScript implementation, so a string compressed in Swift can be decompressed in a browser, and vice versa.

## Features

- **Compatible with the JavaScript original.** Verified against `lz-string` for every format.
- **Six output formats** — Base64, URL-safe, UTF-16, `[UInt8]`, `Data`, and raw `String` (deprecated).
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
    .package(url: "https://github.com/takagi-denki/lzstring-swift.git", from: "1.1.0"),
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
| `compressToUInt8Array` / `decompressFromUInt8Array` | `[UInt8]` | 220 bytes (39%) | You hand the bytes to a JavaScript `Uint8Array` |
| `compress` / `decompress` | `Data` | 220 bytes (39%) | **Most compact.** Writing to a file, a socket, or a database |
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

## Interoperating with JavaScript

Every format round-trips through the original implementation. Compress in Swift:

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

## Caveats

### The raw `String` format is deprecated

`compress(input:) -> String` and `decompress(input: String)` are marked `@available(*, deprecated)` as of 1.1.0. They still work and existing code still builds — you will just get a warning.

They are **not** round-trip safe. The raw 16-bit stream can contain unpaired surrogate code units, and a Swift `String` is guaranteed to be valid Unicode text, so it cannot hold them; they are replaced with `U+FFFD` and the data is destroyed. This is a property of the type, not a bug that can be fixed — a JavaScript string is a sequence of UTF-16 code units and can hold a lone surrogate, but a Swift `String` cannot.

Use `Data`, `[UInt8]`, or `compressToUTF16` when you need a lossless result. See [#22](https://github.com/takagi-denki/lzstring-swift/issues/22).

### Malformed input does not throw

Decompression never traps, but it is **not** a validity check. Given input that is not valid compressed data, it returns either an empty string or a meaningless one — matching the original JavaScript implementation exactly:

```swift
LZString.decompressFromBase64(input: "A")         // ""
LZString.decompressFromBase64(input: "not-valid") // "둞è둞è둞è"
```

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

[WTFPL](http://www.wtfpl.net/) — see [LICENSE.txt](LICENSE.txt).
