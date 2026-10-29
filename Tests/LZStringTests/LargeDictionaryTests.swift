import Testing
import Foundation
@testable import LZString

/// Issue #75 — phrase storage was narrowed from `UInt64` to `UInt16` because phrases hold
/// UTF-16 code units. Dictionary codes are a different thing: they are counters that keep
/// growing, and on a large input they exceed `UInt16.max`.
///
/// This suite decodes an input big enough to push the decoder's dictionary past 65,535
/// entries. An implementation that narrowed the codes along with the literals traps or
/// produces wrong output here.
@Suite("Large dictionary codes")
struct LargeDictionaryTests {
    /// Deterministic high-entropy text. Measured with the decoder instrumented: this input
    /// drives the dictionary to roughly 77,000 entries, comfortably past `UInt16.max`.
    /// High entropy is what matters — repetitive text produces far fewer dictionary codes
    /// for the same length.
    static let text: String = {
        var seed: UInt64 = 42
        var scalars = [Character]()
        scalars.reserveCapacity(150_000)

        for _ in 0..<150_000 {
            seed = seed &* 6364136223846793005 &+ 1
            scalars.append(Character(UnicodeScalar(32 + UInt8(truncatingIfNeeded: seed >> 32) % 90)))
        }

        return String(scalars)
    }()

    @Test("Dictionary codes beyond UInt16.max round-trip")
    func codesBeyondUInt16MaxRoundTrip() {
        let expected = Array(Self.text.utf16)

        let data: Data = LZString.compress(input: Self.text)
        #expect(Array(LZString.decompress(input: data).utf16) == expected)

        #expect(Array(LZString.decompressFromBase64(input: LZString.compressToBase64(input: Self.text)).utf16) == expected)
    }
}
