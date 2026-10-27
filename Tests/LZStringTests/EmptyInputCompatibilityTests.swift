import Testing
import Foundation
@testable import LZString

/// Regression tests for issue #33. The original JavaScript implementation distinguishes
/// an empty string from null and still emits the end-of-stream code for an empty string;
/// the Swift compressors used to return early instead.
///
/// Expected values are fixed outputs from lz-string 1.5.0 under Node. A round-trip test
/// cannot detect this mismatch, so each format's output is compared against JS directly.
@Suite("Empty input compatibility")
struct EmptyInputCompatibilityTests {
    @Test("Base64 output for empty input matches JavaScript")
    func base64MatchesJavaScript() {
        #expect(LZString.compressToBase64(input: "") == "Q===")
    }

    @Test("URI output for empty input matches JavaScript")
    func uriMatchesJavaScript() {
        #expect(LZString.compressToEncodedURIComponent(input: "") == "Q")
    }

    @Test("UTF16 output for empty input matches JavaScript")
    func utf16MatchesJavaScript() {
        #expect(Array(LZString.compressToUTF16(input: "").utf16) == [8224, 32])
    }

    @Test("UInt8Array output for empty input matches JavaScript")
    func uint8ArrayMatchesJavaScript() {
        #expect(LZString.compressToUInt8Array(input: "") == [64, 0])
    }

    /// Data keeps little-endian byte order, so JavaScript's [64, 0] becomes [0, 64].
    @Test("Data output for empty input matches in little-endian order")
    func dataMatchesJavaScript() {
        let compressed: Data = LZString.compress(input: "")
        #expect([UInt8](compressed) == [0, 64])
    }

    /// The raw String format is deprecated (#22), but its output still matches JavaScript.
    @Test("Raw String output for empty input matches JavaScript")
    @available(*, deprecated, message: "Intentional: exercises the deprecated raw String format (#22).")
    func rawStringMatchesJavaScript() {
        let compressed: String = LZString.compress(input: "")
        #expect(Array(compressed.utf16) == [16384])
    }

    /// Compressing empty input and decompressing it again yields an empty string.
    @Test("The compressed form of empty input round-trips")
    func emptyInputRoundTrips() {
        #expect(LZString.decompressFromBase64(input: LZString.compressToBase64(input: "")) == "")
        #expect(LZString.decompressFromEncodedURIComponent(input: LZString.compressToEncodedURIComponent(input: "")) == "")
        #expect(LZString.decompressFromUTF16(input: LZString.compressToUTF16(input: "")) == "")
        #expect(LZString.decompressFromUInt8Array(input: LZString.compressToUInt8Array(input: "")) == "")

        let compressed: Data = LZString.compress(input: "")
        #expect(LZString.decompress(input: compressed) == "")
    }

    /// Payloads for empty input produced by JavaScript decompress correctly here.
    @Test("Decompresses empty-input payloads produced by JavaScript")
    func decompressesJavaScriptProducedEmptyPayloads() {
        #expect(LZString.decompressFromBase64(input: "Q===") == "")
        #expect(LZString.decompressFromEncodedURIComponent(input: "Q") == "")
        #expect(LZString.decompressFromUInt8Array(input: [64, 0]) == "")
        #expect(LZString.decompress(input: Data([0, 64])) == "")
    }

    /// The decompressors' behaviour for empty input is unchanged: they return "".
    /// JavaScript returns null, but the Swift return type is String.
    @Test("Decompressor behaviour for empty input is unchanged")
    func decompressorEmptyInputBehaviourIsUnchanged() {
        #expect(LZString.decompressFromBase64(input: "") == "")
        #expect(LZString.decompressFromEncodedURIComponent(input: "") == "")
        #expect(LZString.decompressFromUTF16(input: "") == "")
        #expect(LZString.decompressFromUInt8Array(input: []) == "")
        #expect(LZString.decompress(input: Data()) == "")
    }
}
