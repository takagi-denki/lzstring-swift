import Testing
import Foundation
@testable import LZString

/// Regression tests for issue #23. The decoded units used to be serialised to bytes and
/// handed to `String(data:encoding:.utf16)`, which ate a leading U+FEFF as a BOM — and
/// read a leading U+FFFE as a little-endian BOM, flipping the byte order of the rest.
///
/// Expected values are produced by the original JavaScript implementation
/// (pieroxy/lz-string 1.5.0).
@Suite("Byte order mark round trip")
struct ByteOrderMarkTests {
    static let cases: [(input: String, base64: String)] = [
        ("\u{FEFF}abc", "v9/EMEYMZA=="),
        ("\u{FEFF}", "v9/Q"),
        ("\u{FEFF}\u{FEFF}", "v9/yA==="),
        ("\u{FEFF}🥺", "v9/j4Nxeu0A="),
        ("ab\u{FEFF}cd", "IYI0/38MYCZA"),
        ("\u{FFFE}abc", "n//EMEYMZA=="),
        ("\u{FFFE}", "n//Q"),
        ("abc", "IYIwxkA="),
    ]

    @Test("Issue #23 minimal reproduction: a leading U+FEFF survives")
    func minimalReproduction() {
        let input = "\u{FEFF}abc"
        let output = LZString.decompressFromBase64(input: LZString.compressToBase64(input: input))

        #expect(Array(output.utf16) == [0xFEFF, 0x61, 0x62, 0x63])
        #expect(output == input)
    }

    /// A leading U+FFFE used to be mistaken for a little-endian BOM, which also
    /// reversed the byte order of everything after it.
    @Test("A leading U+FFFE does not reverse the byte order")
    func leadingReversedByteOrderMark() {
        let input = "\u{FFFE}abc"
        let output = LZString.decompressFromBase64(input: LZString.compressToBase64(input: input))

        #expect(Array(output.utf16) == [0xFFFE, 0x61, 0x62, 0x63])
        #expect(output == input)
    }

    @Test("Compressed output matches JavaScript", arguments: cases)
    func matchesJavaScriptOutput(input: String, expectedBase64: String) {
        #expect(LZString.compressToBase64(input: input) == expectedBase64)
    }

    /// The raw String format is excluded: it replaces surrogates with U+FFFD (issue #22).
    @Test("Round-trips through every lossless format", arguments: cases)
    func roundTripsThroughEveryFormat(input: String, expectedBase64: String) {
        #expect(LZString.decompressFromBase64(input: expectedBase64) == input)
        #expect(LZString.decompressFromEncodedURIComponent(input: LZString.compressToEncodedURIComponent(input: input)) == input)
        #expect(LZString.decompressFromUTF16(input: LZString.compressToUTF16(input: input)) == input)
        #expect(LZString.decompressFromUInt8Array(input: LZString.compressToUInt8Array(input: input)) == input)

        let compressed: Data = LZString.compress(input: input)
        #expect(LZString.decompress(input: compressed) == input)
    }

    /// Confirms surrogate pairs and characters outside the BMP are not damaged.
    @Test("Strings containing surrogate pairs round-trip", arguments: ["🥺", "🥺🥺", "a🥺b", "\u{10FFFF}", "𝄞音符"])
    func supplementaryCharactersRoundTrip(input: String) {
        #expect(LZString.decompressFromBase64(input: LZString.compressToBase64(input: input)) == input)

        let compressed: Data = LZString.compress(input: input)
        #expect(LZString.decompress(input: compressed) == input)
    }

    /// Malformed input still returns an empty string, the failure value set in issue #21.
    @Test("Malformed input still returns an empty string")
    func malformedInputStillReturnsEmptyString() {
        #expect(LZString.decompressFromBase64(input: "!!!!") == "")
        #expect(LZString.decompressFromBase64(input: "A") == "")
    }
}
