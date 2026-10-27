import Testing
import Foundation
@testable import LZString

/// Regression tests for issue #57. The initial two-bit tag only has three valid values;
/// tag 3 had no branch and fell through with the initial `c == 0`, fabricating a NUL
/// character instead of rejecting the stream as the JavaScript original does.
///
/// **A decoded NUL is not itself invalid.** Genuine NUL input must still round-trip,
/// so what gets rejected is the tag, not the result.
@Suite("Invalid initial tag")
struct InvalidTagTests {
    /// The inputs from the issue, each carrying initial tag 3. The expected value comes
    /// from lz-string 1.5.0, which returns an empty string for all of them.
    @Test("Initial tag 3 is rejected in every format")
    func invalidInitialTagIsRejected() {
        #expect(LZString.decompressFromBase64(input: "0A==") == "")
        #expect(LZString.decompressFromEncodedURIComponent(input: "0A") == "")
        #expect(LZString.decompressFromUTF16(input: "\u{6820} ") == "")
        #expect(LZString.decompressFromUInt8Array(input: [0xD0, 0x00]) == "")

        // Data is the little-endian representation of the same stream.
        #expect(LZString.decompress(input: Data([0x00, 0xD0])) == "")
    }

    /// Pins emptiness at the code-unit level too: `== ""` alone is a weak guard against
    /// an implementation regressing to a single NUL character.
    @Test("Rejected input produces no code units")
    func rejectedInputProducesNoCodeUnits() {
        #expect(Array(LZString.decompressFromBase64(input: "0A==").utf16) == [])
        #expect(Array(LZString.decompressFromEncodedURIComponent(input: "0A").utf16) == [])
        #expect(Array(LZString.decompressFromUTF16(input: "\u{6820} ").utf16) == [])
        #expect(Array(LZString.decompressFromUInt8Array(input: [0xD0, 0x00]).utf16) == [])
        #expect(Array(LZString.decompress(input: Data([0x00, 0xD0])).utf16) == [])
    }

    /// Genuine input containing NUL must round-trip through every lossless format.
    /// An implementation that treated a decoded NUL as failure would fail here.
    @Test("Genuine input containing NUL round-trips", arguments: ["\u{0}", "a\u{0}b", "\u{0}\u{0}", "\u{0}abc", "abc\u{0}"])
    func genuineNulInputRoundTrips(input: String) {
        let expected = Array(input.utf16)

        #expect(Array(LZString.decompressFromBase64(input: LZString.compressToBase64(input: input)).utf16) == expected)
        #expect(Array(LZString.decompressFromEncodedURIComponent(input: LZString.compressToEncodedURIComponent(input: input)).utf16) == expected)
        #expect(Array(LZString.decompressFromUTF16(input: LZString.compressToUTF16(input: input)).utf16) == expected)
        #expect(Array(LZString.decompressFromUInt8Array(input: LZString.compressToUInt8Array(input: input)).utf16) == expected)

        let data: Data = LZString.compress(input: input)
        #expect(Array(LZString.decompress(input: data).utf16) == expected)
    }

    /// Confirms the valid tag 0 / 1 / 2 paths are intact.
    @Test("Valid initial tag paths are preserved")
    func validInitialTagsStillWork() {
        // Tag 0: 8-bit literal (U+0000 through U+00FF).
        #expect(LZString.decompressFromBase64(input: LZString.compressToBase64(input: "a")) == "a")
        #expect(LZString.decompressFromBase64(input: LZString.compressToBase64(input: "\u{FF}")) == "\u{FF}")

        // Tag 1: 16-bit literal (U+0100 and above).
        #expect(LZString.decompressFromBase64(input: LZString.compressToBase64(input: "\u{100}")) == "\u{100}")
        #expect(LZString.decompressFromBase64(input: LZString.compressToBase64(input: "あ")) == "あ")

        // Tag 2: the end-of-stream code for empty input (issue #33).
        #expect(LZString.compressToBase64(input: "") == "Q===")
        #expect(LZString.decompressFromBase64(input: "Q===") == "")
    }
}
