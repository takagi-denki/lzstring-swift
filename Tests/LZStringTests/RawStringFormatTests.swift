import Testing
import Foundation
@testable import LZString

/// Issue #22 — pins the limitation of the raw `String` format. Swift's `String` cannot hold unpaired
/// UTF-16 surrogates, so they are replaced with `U+FFFD` and the data is destroyed.
/// The format is deprecated in favour of the lossless ones.
@Suite("Raw String format")
struct RawStringFormatTests {
    /// The reproduction input from issue #22; its fourth code unit is a surrogate.
    static let input = "test1111"

    @Test("The raw String format loses surrogates and cannot round-trip")
    @available(*, deprecated, message: "Intentional: exercises the deprecated raw String format (#22).")
    func rawStringFormatIsLossy() {
        let compressed: String = LZString.compress(input: Self.input)

        // The fourth unit should be 55616 (0xD940); being a lone surrogate it becomes U+FFFD.
        #expect(Array(compressed.utf16) == [2949, 12494, 49292, 0xFFFD])
        #expect(LZString.decompress(input: compressed) != Self.input)
    }

    /// Guarantees the same input round-trips correctly through the lossless formats.
    @Test("The same input round-trips through the lossless formats")
    func losslessFormatsRoundTripTheSameInput() {
        let data: Data = LZString.compress(input: Self.input)
        let units = stride(from: 0, to: data.count, by: 2).map { Int(data[$0]) | (Int(data[$0 + 1]) << 8) }

        // The Data format preserves the surrogate value as-is.
        #expect(units == [2949, 12494, 49292, 55616])
        #expect(LZString.decompress(input: data) == Self.input)

        #expect(LZString.decompressFromUInt8Array(input: LZString.compressToUInt8Array(input: Self.input)) == Self.input)
        #expect(LZString.decompressFromUTF16(input: LZString.compressToUTF16(input: Self.input)) == Self.input)
        #expect(LZString.decompressFromBase64(input: LZString.compressToBase64(input: Self.input)) == Self.input)
        #expect(LZString.decompressFromEncodedURIComponent(input: LZString.compressToEncodedURIComponent(input: Self.input)) == Self.input)
    }
}
