import Testing
import Foundation
@testable import LZString

/// Regression tests for issue #21. Truncated or malformed input used to read past
/// the end of the buffer and terminate the process.
///
/// The documented failure result is an empty string, matching the original
/// JavaScript implementation (pieroxy/lz-string 1.5.0) for the same inputs.
@Suite("Truncated input")
struct TruncatedInputTests {
    static let text = "Lorem ipsum dolor sit amet, consectetur adipiscing elit"
    static let validBase64 = "DIewTgpgtgBAlgBwM4FdYBMQBtwyXAFxgEMoICAaGAYxADskJqDyUwT1E4lq46BzGBCyEgA="

    @Test("Issue #21 minimal reproduction: a one-character Base64 input does not trap")
    func minimalReproduction() {
        #expect(LZString.decompressFromBase64(input: "A") == "")
    }

    @Test("Truncated and malformed input returns an empty string in every format")
    @available(*, deprecated, message: "Intentional: covers the raw String format (#22).")
    func malformedInputReturnsEmptyString() {
        #expect(LZString.decompressFromBase64(input: "A") == "")
        #expect(LZString.decompressFromBase64(input: "!!!!") == "")
        #expect(LZString.decompressFromEncodedURIComponent(input: "A") == "")
        #expect(LZString.decompressFromUTF16(input: "A") == "")
        #expect(LZString.decompress(input: "A") == "")
    }

    /// A one-byte input passes the public `!input.isEmpty` guard and used to trap when
    /// the second byte of the pair was read.
    @Test("Byte input shorter than one code unit does not trap")
    func binaryInputShorterThanOneCodeUnit() {
        #expect(LZString.decompressFromUInt8Array(input: [0x01]) == "")
        #expect(LZString.decompress(input: Data([0x01])) == "")
    }

    /// The smallest prefix of this payload that still decodes: stripping padding and
    /// unused trailing bits leaves a complete stream, so a shorter prefix still works.
    /// Named as a measured boundary rather than left as a magic number (issue #42).
    static let smallestDecodablePrefix = 70

    /// Tries every truncation of a valid payload. A single trap would take down the test
    /// process, so the sweep itself is the regression check.
    @Test("Input truncated to any length does not trap")
    func everyTruncationIsSafe() {
        for length in 1...Self.validBase64.count {
            let truncated = String(Self.validBase64.prefix(length))
            let decoded = LZString.decompressFromBase64(input: truncated)

            // A truncated input yields either the full text or an empty string, never
            // partially decoded, corrupted text.
            #expect(decoded.isEmpty || decoded == Self.text,
                    "length=\(length): partial result \(decoded.debugDescription)")

            // The boundary must match the measured value.
            #expect((decoded == Self.text) == (length >= Self.smallestDecodablePrefix),
                    "length=\(length): the boundary assumption no longer holds")
        }
    }

    /// Pins the decoding boundary itself.
    @Test("The smallest decodable prefix boundary")
    func decodingBoundaryIsPinned() {
        #expect(LZString.decompressFromBase64(input: String(Self.validBase64.prefix(Self.smallestDecodablePrefix))) == Self.text)
        #expect(LZString.decompressFromBase64(input: String(Self.validBase64.prefix(Self.smallestDecodablePrefix - 1))) == "")
    }

    /// Confirms the added bounds checks did not break valid input that consumes its last
    /// bit exactly at the end of the stream.
    @Test("Valid input ending exactly on a boundary still decodes")
    func validInputAtExactBufferBoundaryStillDecodes() {
        #expect(LZString.decompressFromBase64(input: Self.validBase64) == Self.text)

        for input in ["a", "aa", "ab", "hello world", "ああ", "🥺"] {
            #expect(LZString.decompressFromBase64(input: LZString.compressToBase64(input: input)) == input)
            #expect(LZString.decompressFromEncodedURIComponent(input: LZString.compressToEncodedURIComponent(input: input)) == input)
            #expect(LZString.decompressFromUTF16(input: LZString.compressToUTF16(input: input)) == input)
            #expect(LZString.decompressFromUInt8Array(input: LZString.compressToUInt8Array(input: input)) == input)

            let compressed: Data = LZString.compress(input: input)
            #expect(LZString.decompress(input: compressed) == input)
        }
    }
}
