import Testing
import Foundation
@testable import LZString

/// Regression tests for issue #32. A sliced `Data` does not start at index 0, and the
/// decoder assumed zero-based indices, so even a complete payload trapped. This is
/// distinct from issue #21, which was about truncated input.
@Suite("Decompressing Data slices")
struct DataSliceTests {
    static let text = "hello"

    /// The minimal reproduction from the issue: a payload with a two-byte header stripped.
    @Test("Issue #32 minimal reproduction: a slice past a header decompresses")
    func minimalReproduction() {
        let encoded: Data = LZString.compress(input: Self.text)

        var packet = Data([0, 0])
        packet.append(encoded)

        let payload = packet.dropFirst(2)
        #expect(payload.startIndex == 2)
        #expect(LZString.decompress(input: payload) == Self.text)
    }

    /// A slice and the same bytes rebased to index 0 must produce the same result.
    @Test("A slice and a rebased Data agree", arguments: [0, 1, 2, 3, 7, 16])
    func sliceMatchesRebasedData(offset: Int) {
        let encoded: Data = LZString.compress(input: Self.text)

        var packet = Data(repeating: 0xAB, count: offset)
        packet.append(encoded)

        let slice = packet.dropFirst(offset)
        #expect(slice.startIndex == offset)
        #expect(LZString.decompress(input: slice) == Self.text)
        #expect(LZString.decompress(input: slice) == LZString.decompress(input: Data(slice)))
    }

    /// A slice taken from the end must not assume zero-based indices either.
    @Test("A trailing slice does not trap")
    func trailingSliceIsSafe() {
        let encoded: Data = LZString.compress(input: Self.text)

        var packet = encoded
        packet.append(contentsOf: [0xFF, 0xFF])

        let payload = packet.dropLast(2)
        #expect(LZString.decompress(input: payload) == Self.text)
    }

    /// Preserves the failure behaviour set in issue #21 — empty string, never a trap.
    @Test("Empty, one-byte and truncated slices do not trap")
    func degenerateSlicesPreserveFailureBehaviour() {
        let encoded: Data = LZString.compress(input: Self.text)
        var packet = Data([0, 0])
        packet.append(encoded)

        #expect(LZString.decompress(input: packet.dropFirst(packet.count)) == "")
        #expect(LZString.decompress(input: packet.dropFirst(packet.count - 1)) == "")

        // Slices truncated to every length; a single trap would fail the whole run.
        for length in 0...encoded.count {
            _ = LZString.decompress(input: packet.dropFirst(2).prefix(length))
        }
    }

    /// Non-ASCII input and surrogate pairs also round-trip through a slice.
    @Test("Various inputs round-trip through a slice", arguments: ["a", "aaa", "ああ", "🥺", "\u{FEFF}abc", "Lorem ipsum dolor sit amet"])
    func sliceRoundTripsVariousInputs(input: String) {
        let encoded: Data = LZString.compress(input: input)

        var packet = Data([0xDE, 0xAD, 0xBE, 0xEF])
        packet.append(encoded)

        #expect(LZString.decompress(input: packet.dropFirst(4)) == input)
    }
}
