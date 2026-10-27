import Testing
import Foundation
@testable import LZString

/// Regression tests for issue #20. Repeated characters hit the LZW KwKwK case,
/// which used to trap with `Index out of range` during decompression.
///
/// Expected values are produced by the original JavaScript implementation
/// (pieroxy/lz-string 1.5.0).
@Suite("Repeated characters")
struct RepeatedCharacterTests {
    static let cases: [(input: String, base64: String, uri: String)] = [
        ("aa", "IbI=", "IbI"),
        ("aaa", "IYo=", "IYo"),
        ("aaaa", "IY5A", "IY5A"),
        ("ababab", "IYI1qA==", "IYI1qA"),
        ("abcabcabc", "IYIwxqHkA===", "IYIwxqHkA"),
        ("aaa bbb aaa bbb", "IYgECNNFgyg=", "IYgECNNFgyg"),
        ("ああああ", "kIMOQ===", "kIMOQ"),
        ("🥺🥺🥺", "nwbi9d2o", "nwbi9d2o"),
    ]

    @Test("Issue #20 minimal reproduction: \"aaa\" round-trips")
    func minimalReproduction() {
        let encoded = LZString.compressToBase64(input: "aaa")
        #expect(encoded == "IYo=")
        #expect(LZString.decompressFromBase64(input: encoded) == "aaa")
    }

    @Test("Compressed output matches JavaScript", arguments: cases)
    func matchesJavaScriptOutput(input: String, expectedBase64: String, expectedUri: String) {
        #expect(LZString.compressToBase64(input: input) == expectedBase64)
        #expect(LZString.compressToEncodedURIComponent(input: input) == expectedUri)
    }

    /// Checks the round trip through every lossless format. The raw String format is
    /// excluded: it replaces surrogates with U+FFFD, a known limitation (issue #22).
    @Test("Round-trips through every lossless format", arguments: cases)
    func roundTripsThroughEveryFormat(input: String, expectedBase64: String, expectedUri: String) {
        #expect(LZString.decompressFromBase64(input: expectedBase64) == input)
        #expect(LZString.decompressFromEncodedURIComponent(input: expectedUri) == input)
        #expect(LZString.decompressFromUTF16(input: LZString.compressToUTF16(input: input)) == input)
        #expect(LZString.decompressFromUInt8Array(input: LZString.compressToUInt8Array(input: input)) == input)

        let compressed: Data = LZString.compress(input: input)
        #expect(LZString.decompress(input: compressed) == input)
    }

    @Test("A long run of repeated characters round-trips")
    func longRunOfRepeatedCharacters() {
        let input = String(repeating: "x", count: 500)
        #expect(LZString.compressToBase64(input: input) == "B418ZXTt/DFOS1b0c17Pd/wYWEA=")
        #expect(LZString.decompressFromBase64(input: LZString.compressToBase64(input: input)) == input)
    }
}
