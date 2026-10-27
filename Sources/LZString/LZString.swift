import Foundation

private let keyStrBase64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/="
private let keyStrBase64Array = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 62, 0, 0, 0, 63, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 0, 0, 0, 64, 0, 0, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 0, 0, 0, 0, 0, 0, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
private let keyStrUriSafe = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+-$"
private let keyStrUriSafeArray = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 64, 0, 0, 0, 0, 0, 0, 62, 0, 63, 0, 0, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 0, 0, 0, 0, 0, 0, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]


private func getCharFromInt(_ a: Int) -> Character {
    if let scalar = Unicode.Scalar(a) {
        return Character(scalar)
    } else {
        return Character("\u{FFFD}")
    }
}

private typealias GetCharFromInt<T> = (Int) -> T
private typealias GetNextValue = (Int) -> Int

private typealias DecompressData = (value: Int, position: Int, index: Int)
private typealias CompressContext<T> = (dict: [String:Int], dictCreate: [String:Bool], data: T, val: Int, position: Int) where T : RangeReplaceableCollection

private func getBaseValue(alphabet: [Int], char: Character) -> Int {
    guard let ascii = char.asciiValue else {
        return 0
    }

    return alphabet[Int(ascii)]
}

/// Compresses `input` into a string drawn from a Base64 alphabet.
///
/// The result is not a Base64 encoding of `input`. It is the LZ-compressed bit stream
/// rendered with the Base64 alphabet (`A`–`Z`, `a`–`z`, `0`–`9`, `+`, `/`, padded with
/// `=`), so a general-purpose Base64 decoder does not recover the original text. Reverse
/// it with `decompressFromBase64(input:)`.
///
/// Compressing an empty string still emits an end-of-stream code, so the result is not
/// empty: `compressToBase64(input: "")` returns `"Q==="`.
///
///     let compressed = LZString.compressToBase64(input: "Hello, World!")
///     // "BIUwNmD2A0AEDqkBOYAmBCIA"
///
/// - Parameter input: The text to compress.
/// - Returns: The compressed stream written in the Base64 alphabet.
public func compressToBase64(input: String) -> String {
    let result = _compress(input: input, bitPerChar: 6, charFromInt: { a in String(keyStrBase64[a])})
    switch result.count % 4 {
    case 0:
        return result
    case 1:
        return result + "==="
    case 2:
        return result + "=="
    case 3:
        return result + "="
    default:
        return ""
    }
}

/// Decompresses a stream produced by `compressToBase64(input:)`.
///
/// This function does not validate its argument. Input that is not a valid compressed
/// stream returns an empty string or meaningless text rather than reporting an error, and
/// an empty argument returns an empty string. Because a failure is reported as `""`, a
/// successful decode of empty original text cannot be distinguished from a failure by the
/// return value alone.
///
/// - Parameter input: A stream produced by `compressToBase64(input:)`, or by the matching
///   function of the original lz-string implementation.
/// - Returns: The original text, or an empty string if the input could not be decoded.
public func decompressFromBase64(input: String) -> String {
    guard !input.isEmpty else {
        return ""
    }

    return _decompress(length: input.count, resetValue: 32, nextValue: { a in getBaseValue(alphabet: keyStrBase64Array, char: input[a]) })
}

/// Compresses `input` into a string that packs 15 bits into each UTF-16 code unit.
///
/// Unlike the deprecated raw `String` format, this representation is lossless, which makes
/// it the compact choice when the destination counts characters rather than bytes.
///
/// The result ends with a trailing space that belongs to the format's output. Treat the
/// returned string as opaque and pass it back to `decompressFromUTF16(input:)` unchanged;
/// trimming or otherwise normalising it is not a supported use.
///
/// Compressing an empty string still emits an end-of-stream code, so the result is not
/// empty.
///
/// - Parameter input: The text to compress.
/// - Returns: The compressed stream as 15-bit-packed UTF-16 code units.
public func compressToUTF16(input: String) -> String {
    return _compress(input: input, bitPerChar: 15, charFromInt: { a in String(getCharFromInt(a + 32))}) + " "
}

/// Decompresses a stream produced by `compressToUTF16(input:)`.
///
/// This function does not validate its argument. Input that is not a valid compressed
/// stream returns an empty string or meaningless text rather than reporting an error, and
/// an empty argument returns an empty string. Because a failure is reported as `""`, a
/// successful decode of empty original text cannot be distinguished from a failure by the
/// return value alone.
///
/// - Parameter input: A stream produced by `compressToUTF16(input:)`, or by the matching
///   function of the original lz-string implementation.
/// - Returns: The original text, or an empty string if the input could not be decoded.
public func decompressFromUTF16(input: String) -> String {
    guard !input.isEmpty else {
        return ""
    }

    return _decompress(length: input.utf16.count, resetValue: 16384, nextValue: { i in Int(input.utf16[i]) - 32 })
}

/// Compresses `input` into bytes laid out like the original implementation's
/// `Uint8Array`.
///
/// Each 16-bit unit of the compressed stream is stored **big-endian**, matching the
/// JavaScript `compressToUint8Array`. This differs from `compress(input:)` returning
/// `Data`, which stores the same stream little-endian. Converting between the two with
/// `Data(_:)` or `[UInt8](_:)` alone does not reorder the bytes, so the result cannot be
/// read by the other format's decompressor.
///
/// Compressing an empty string still emits an end-of-stream code, so the result is not
/// empty: `compressToUInt8Array(input: "")` returns `[64, 0]`.
///
/// - Parameter input: The text to compress.
/// - Returns: The compressed stream as big-endian 16-bit units.
public func compressToUInt8Array(input: String) -> [UInt8] {
    let compressed : Data = compress(input: input)
    var buffer = [UInt8](repeating: 0, count: compressed.count)

    for i in 0..<(compressed.count / 2) {
        buffer[i * 2] = compressed[i * 2 + 1]
        buffer[i * 2 + 1] = compressed[i * 2]
    }

    return buffer
}

/// Decompresses bytes produced by `compressToUInt8Array(input:)`.
///
/// The bytes are read as **big-endian** 16-bit units. Passing the little-endian bytes of
/// `compress(input:)` returning `Data` without reordering them does not decode correctly.
///
/// This function does not validate its argument. Input that is not a valid compressed
/// stream returns an empty string or meaningless text rather than reporting an error, and
/// an empty argument returns an empty string. Because a failure is reported as `""`, a
/// successful decode of empty original text cannot be distinguished from a failure by the
/// return value alone.
///
/// - Parameter input: Bytes produced by `compressToUInt8Array(input:)`, or by the matching
///   function of the original lz-string implementation.
/// - Returns: The original text, or an empty string if the input could not be decoded.
public func decompressFromUInt8Array(input: [UInt8]) -> String {
    guard !input.isEmpty else {
        return ""
    }

    return _decompress(length: input.count / 2, resetValue: 32768, nextValue: {i in
        let lower = Int(input[i * 2]) * 256
        let upper = Int(input[i * 2 + 1])
        return upper + lower
    })
}

/// Compresses `input` into a string that can be placed in a URL query component.
///
/// The alphabet is `A`–`Z`, `a`–`z`, `0`–`9`, `+`, `-`, `$`, with no `/` and no `=`
/// padding. This is neither Base64URL nor percent-encoding, and the result is not a
/// percent-encoded form of `input`.
///
/// The alphabet does contain `+`. Some URL decoders turn `+` into a space;
/// `decompressFromEncodedURIComponent(input:)` converts spaces back to `+`, so a value
/// that went through such a decoder still decodes.
///
/// Compressing an empty string still emits an end-of-stream code, so the result is not
/// empty: `compressToEncodedURIComponent(input: "")` returns `"Q"`.
///
/// - Parameter input: The text to compress.
/// - Returns: The compressed stream written in the URL-safe alphabet.
public func compressToEncodedURIComponent(input: String) -> String {
    return _compress(input: input, bitPerChar: 6, charFromInt: { i in String(keyStrUriSafe[i])})
}

/// Decompresses a stream produced by `compressToEncodedURIComponent(input:)`.
///
/// Every space in the input is converted to `+` before decoding, which restores values
/// whose `+` characters were turned into spaces by a URL decoder.
///
/// This function does not validate its argument. Input that is not a valid compressed
/// stream returns an empty string or meaningless text rather than reporting an error, and
/// an empty argument returns an empty string. Because a failure is reported as `""`, a
/// successful decode of empty original text cannot be distinguished from a failure by the
/// return value alone.
///
/// - Parameter input: A stream produced by `compressToEncodedURIComponent(input:)`, or by
///   the matching function of the original lz-string implementation.
/// - Returns: The original text, or an empty string if the input could not be decoded.
public func decompressFromEncodedURIComponent(input: String) -> String {
    guard !input.isEmpty else {
        return ""
    }

    let replaced = input.replacingOccurrences(of: " ", with: "+")

    return _decompress(length: replaced.count, resetValue: 32, nextValue: { a in getBaseValue(alphabet: keyStrUriSafeArray, char: replaced[a]) })
}

/// Returns the raw 16-bit compressed stream as a `String`.
///
/// `compress(input:)` is overloaded on its return type, so the call site must state which
/// one it wants. Prefer the `Data` overload: `let compressed: Data = LZString.compress(...)`.
///
/// - Warning: This format is **lossy**. The stream can contain unpaired UTF-16 surrogate
///   code units, which a Swift `String` cannot represent; they are replaced with `U+FFFD`
///   and the data is destroyed. This is a property of the type rather than a defect that
///   can be fixed here. Use a lossless format instead: `compress(input:)` returning `Data`,
///   `compressToUInt8Array(input:)`, or `compressToUTF16(input:)`.
///
/// - Parameter input: The text to compress.
/// - Returns: The compressed stream as a `String`, with any unpaired surrogate code unit
///   replaced by `U+FFFD`.
@available(*, deprecated, message: "Lossy: the raw 16-bit stream can contain unpaired surrogates, which a Swift String cannot represent. Use compress(input:) -> Data, compressToUInt8Array(input:), or compressToUTF16(input:).")
public func compress(input: String) -> String {
    return _compress(input: input, bitPerChar: 16, charFromInt: { a in String(getCharFromInt(a)) })
}

/// Compresses `input` into the most compact representation this library offers.
///
/// Each 16-bit unit of the compressed stream is stored **little-endian**. This differs from
/// `compressToUInt8Array(input:)`, which stores the same stream big-endian for compatibility
/// with the original implementation; converting between the two with `Data(_:)` or
/// `[UInt8](_:)` alone does not reorder the bytes.
///
/// `compress(input:)` is overloaded on its return type, so the call site must state which
/// one it wants:
///
///     import Foundation
///
///     let compressed: Data = LZString.compress(input: "Hello, World!")
///     let original = LZString.decompress(input: compressed)
///     // "Hello, World!"
///
/// Compressing an empty string still emits an end-of-stream code, so the result is not
/// empty: it is the two bytes `[0, 64]`.
///
/// - Parameter input: The text to compress.
/// - Returns: The compressed stream as little-endian 16-bit units.
public func compress(input: String) -> Data {
    return _compress(input: input, bitPerChar: 16, charFromInt: { a in
        return Data([UInt8(a % 256), UInt8(a >> 8)])
    })
}

// TODO: Change Generics
private func _compress<T : RangeReplaceableCollection>(input: String, bitPerChar: Int, charFromInt: GetCharFromInt<T>) -> T {
    // No early return for an empty string: the original JS distinguishes "" from null
    // and still emits the end-of-stream code for "" (issue #33).
    var value = 0
    var wc : [UInt16] = []
    var w : [UInt16] = []
    var enlargeIn = 2
    var dictSize = 3
    var numBits = 2
    var context = (dict: [[UInt16]:Int](), dictCreate: [[UInt16]:Bool](), data: T(), val: 0, position: 0)

    for c in input.utf16 {
        let s = [c]

        if context.dict.index(forKey: s) == nil {
            context.dict[s] = dictSize
            context.dictCreate[s] = true
            dictSize += 1
        }

        wc = w + s

        if context.dict[wc] != nil {
            w = wc
        } else {
            if context.dictCreate.index(forKey: w) != nil {
                if w[0] < 256 {
                    for _ in 0..<numBits {
                        context.val <<= 1

                        if context.position == bitPerChar - 1 {
                            context.position = 0
                            context.data += charFromInt(context.val)
                            context.val = 0
                        } else {
                            context.position += 1
                        }
                    }

                    value = Int(w[0])

                    for _ in 0..<8 {
                        context.val = (context.val << 1) | (value & 1)

                        if context.position == bitPerChar - 1 {
                            context.position = 0
                            context.data += charFromInt(context.val)
                            context.val = 0
                        } else {
                            context.position += 1
                        }

                        value >>= 1
                    }
                } else {
                    value = 1

                    for _ in 0..<numBits {
                        context.val = (context.val << 1) | value

                        if context.position == bitPerChar - 1 {
                            context.position = 0
                            context.data += charFromInt(context.val)
                            context.val = 0
                        } else {
                            context.position += 1
                        }
                        value = 0
                    }

                    value = Int(w[0])

                    for _ in 0..<16 {
                        context.val = (context.val << 1) | (value & 1)

                        if context.position == bitPerChar - 1 {
                            context.position = 0
                            context.data += charFromInt(context.val)
                            context.val = 0
                        } else {
                            context.position += 1
                        }

                        value >>= 1
                    }
                }

                enlargeIn -= 1

                if enlargeIn == 0 {
                    enlargeIn = 2 << (numBits - 1)
                    numBits += 1
                }

                context.dictCreate.removeValue(forKey: w)
            } else {
                value = context.dict[w]!

                for _ in 0..<numBits {
                    context.val = (context.val << 1) | (value & 1)

                    if context.position == bitPerChar - 1 {
                        context.position = 0
                        context.data += charFromInt(context.val)
                        context.val = 0
                    } else {
                        context.position += 1
                    }

                    value >>= 1
                }
            }
            enlargeIn -= 1

            if enlargeIn == 0 {
                enlargeIn = 2 << (numBits - 1)
                numBits += 1
            }
            context.dict[wc] = dictSize
            dictSize += 1
            w = s
        }
    }

    if !w.isEmpty {
        if context.dictCreate.index(forKey: w) != nil {
            if w[0] < 256 {
                for _ in 0..<numBits {
                    context.val <<= 1

                    if context.position == bitPerChar - 1 {
                        context.position = 0
                        context.data += charFromInt(context.val)
                        context.val = 0
                    } else {
                        context.position += 1
                    }
                }

                value = Int(w[0])

                for _ in 0..<8 {
                    context.val = (context.val << 1) | (value & 1)

                    if context.position == bitPerChar - 1 {
                        context.position = 0
                        context.data += charFromInt(context.val)
                        context.val = 0
                    } else {
                        context.position += 1
                    }

                    value >>= 1
                }
            } else {
                value = 1

                for _ in 0..<numBits {
                    context.val = (context.val << 1) | value

                    if context.position == bitPerChar - 1 {
                        context.position = 0
                        context.data += charFromInt(context.val)
                        context.val = 0
                    } else {
                        context.position += 1
                    }

                    value = 0
                }

                value = Int(w[0])

                for _ in 0..<16 {
                    context.val = (context.val << 1) | (value & 1)

                    if context.position == bitPerChar - 1 {
                        context.position = 0
                        context.data += charFromInt(context.val)
                        context.val = 0
                    } else {
                        context.position += 1
                    }

                    value >>= 1
                }
            }

            enlargeIn -= 1

            if enlargeIn == 0 {
                enlargeIn = 2 << (numBits - 1)
                numBits += 1
            }

            context.dictCreate.removeValue(forKey: w)
        } else {
            value = context.dict[w]!

            for _ in 0..<numBits {
                context.val = (context.val << 1) | (value & 1)

                if context.position == bitPerChar - 1 {
                    context.position = 0
                    context.data += charFromInt(context.val)
                    context.val = 0
                } else {
                    context.position += 1
                }

                value >>= 1
            }
        }

        enlargeIn -= 1

        if enlargeIn == 0 {
            enlargeIn = 2 << (numBits - 1)
            numBits += 1
        }
    }
    value = 2

    for _ in 0..<numBits {
        context.val = (context.val << 1) | (value & 1)

        if context.position == bitPerChar - 1 {
            context.position = 0
            context.data += charFromInt(context.val)
            context.val = 0
        } else {
            context.position += 1
        }

        value >>= 1
    }

    while true {
        context.val <<= 1

        if context.position == bitPerChar - 1 {
            context.data += charFromInt(context.val)
            break
        } else {
            context.position += 1
        }
    }

    return context.data
}

/// Decompresses the raw 16-bit stream from a `String`.
///
/// - Warning: Its counterpart, `compress(input:)` returning `String`, is **lossy**, so a
///   round trip through this format can lose data. Use a lossless format instead:
///   `decompress(input:)` taking `Data`, `decompressFromUInt8Array(input:)`, or
///   `decompressFromUTF16(input:)`.
///
/// This function does not validate its argument. Input that is not a valid compressed
/// stream returns an empty string or meaningless text rather than reporting an error, and
/// an empty argument returns an empty string. Because a failure is reported as `""`, a
/// successful decode of empty original text cannot be distinguished from a failure by the
/// return value alone.
///
/// - Parameter input: A stream produced by `compress(input:)` returning `String`.
/// - Returns: The original text, or an empty string if the input could not be decoded.
@available(*, deprecated, message: "Lossy counterpart of the deprecated compress(input:) -> String. Use decompress(input: Data), decompressFromUInt8Array(input:), or decompressFromUTF16(input:).")
public func decompress(input: String) -> String {
    guard !input.isEmpty else {
        return ""
    }

    return _decompress(length: input.utf16.count, resetValue: 32768, nextValue: {i in Int(input.utf16[i])})
}

/// Decompresses data produced by `compress(input:)` returning `Data`.
///
/// The bytes are read as **little-endian** 16-bit units. Passing the big-endian bytes of
/// `compressToUInt8Array(input:)` without reordering them does not decode correctly.
///
/// A sliced `Data` whose `startIndex` is not zero is handled correctly; no copy is needed.
///
/// This function does not validate its argument. Input that is not a valid compressed
/// stream returns an empty string or meaningless text rather than reporting an error, and
/// an empty argument returns an empty string. Because a failure is reported as `""`, a
/// successful decode of empty original text cannot be distinguished from a failure by the
/// return value alone.
///
/// - Parameter input: Data produced by `compress(input:)` returning `Data`.
/// - Returns: The original text, or an empty string if the input could not be decoded.
public func decompress(input: Data) -> String {
    guard !input.isEmpty else {
        return ""
    }

    // A sliced Data does not start at index 0 (dropFirst, stripping a packet header),
    // so offsets are taken relative to startIndex rather than assuming zero-based
    // indices. No copy required.
    let start = input.startIndex

    return _decompress(length: input.count / 2, resetValue: 32768, nextValue: {i in
        let lower = Int(input[start + i * 2])
        let upper = Int(input[start + i * 2 + 1])  * 256
        return upper + lower
    })
}

private func _decompress(length: Int, resetValue: Int, nextValue: @escaping GetNextValue) -> String {
    var dict : [Int:[UInt64]] = [0 : [0], 1 : [1], 2 : [2]]
    var next = 0
    var enlargeIn = 4
    var dictSize = 4
    var numBits = 3
    var c : UInt64 = 0
    var entry : [UInt64] = []
    var w : [UInt64] = []
    // Accumulate UTF-16 code units directly: going through bytes and
    // String(data:encoding:.utf16) makes a leading U+FEFF / U+FFFE be eaten as a BOM
    // and lost (issue #23).
    var result : [UInt16] = []
    // position = 0 means "buffer empty"; the first read is deferred to _slide so that
    // a zero-length input never indexes out of bounds.
    var data = (value: 0, position: 0, index: 0)

    /// Reads `maxpower` worth of bits, or returns nil when the input is exhausted.
    func _slide(data: inout DecompressData, maxpower: Int) -> Int? {
        var bits = 0
        var power = 1

        while power != maxpower {
            // Refill only when a bit is actually needed, so a stream that ends exactly
            // on a buffer boundary never triggers a read past the end.
            if data.position == 0 {
                guard data.index < length else {
                    return nil
                }

                data.position = resetValue
                data.value = nextValue(data.index)
                data.index += 1
            }

            let resb = data.value & data.position
            data.position >>= 1

            bits |= (resb > 0 ? 1 : 0) * power
            power <<= 1
        }

        return bits
    }

    guard let header = _slide(data: &data, maxpower: 2 << 1) else {
        return ""
    }

    next = header

    // The initial tag is 0 = 8-bit literal, 1 = 16-bit literal, 2 = end of stream.
    // Tag 3 is invalid and must not be treated as a character; it previously fell through
    // with the initial c == 0 and produced a fabricated NUL character (issue #57).
    // A switch keeps the handling exhaustive.
    switch next {
    case 0:
        guard let literal = _slide(data: &data, maxpower: 2 << 7) else {
            return ""
        }

        c = UInt64(literal)
    case 1:
        guard let literal = _slide(data: &data, maxpower: 2 << 15) else {
            return ""
        }

        c = UInt64(literal)
    case 2:
        // An empty stream.
        return ""
    default:
        return ""
    }

    w = [c]
    dict[3] = w
    result.append(contentsOf: w.map({ UInt16($0) }))

    while true {
        // Exhaustion is detected by _slide itself.
        guard let code = _slide(data: &data, maxpower: 2 << (numBits - 1)) else {
            return ""
        }

        c = UInt64(code)

        if c == 0 {
            guard let literal = _slide(data: &data, maxpower: 2 << 7) else {
                return ""
            }

            dict[dictSize] = [UInt64(literal)]
            dictSize += 1
            c = UInt64(dictSize - 1)
            enlargeIn -= 1
        } else if c == 1 {
            guard let literal = _slide(data: &data, maxpower: 2 << 15) else {
                return ""
            }

            dict[dictSize] = [UInt64(literal)]
            dictSize += 1
            c = UInt64(dictSize - 1)
            enlargeIn -= 1
        } else if c == 2 {
            return String(decoding: result, as: UTF16.self)
        }

        if enlargeIn == 0 {
            enlargeIn = 2 << (numBits - 1)
            numBits += 1
        }

        if let e = dict[Int(c)] {
            entry = e
        } else {
            if c == dictSize {
                // LZW KwKwK case: the entry is w + w[0]; `entry` still holds the
                // previous iteration's value (empty on the first pass) and must not be used.
                var tmp = Array(w)
                tmp.append(w[0])
                entry = tmp
            } else {
                return ""
            }
        }

        result.append(contentsOf: entry.map({ UInt16($0) }))
        var tmp = Array(w)
        tmp.append(entry[0])
        dict[dictSize] = tmp
        dictSize += 1
        enlargeIn -= 1
        w = entry

        if enlargeIn == 0 {
            enlargeIn = 2 << (numBits - 1)
            numBits += 1
        }
    }
}

extension String {
    subscript(pos: Int) -> Character {
        return self[String.Index(utf16Offset: pos, in: self)]
    }
}

extension String.UTF16View {
    subscript(pos: Int) -> Unicode.UTF16.CodeUnit {
        return self[String.UTF16View.Index(utf16Offset: pos, in: String(self))]
    }
}
