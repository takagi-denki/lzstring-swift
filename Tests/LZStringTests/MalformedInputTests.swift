import Testing
import Foundation
@testable import LZString

/// Issue #42 — truncation and malformed-input coverage for every decoder.
///
/// This widens coverage rather than replacing the #21 / #32 regressions; the existing
/// suite exhaustively truncated only one Base64 payload.
///
/// Read boundaries differ per format: characters for Base64 and URI, **code units** for
/// UTF16 (`String.prefix` counts Characters, so it is not used), bytes for Data and
/// UInt8Array.
///
/// Expected values are fixed outputs from lz-string 1.5.0 under Node.
@Suite("Malformed and truncated input coverage")
struct MalformedInputTests {
    struct Vector: Sendable, CustomStringConvertible {
        let input: String
        let base64: String
        let uri: String
        let utf16Units: [UInt16]
        let uint8: [UInt8]
        /// Truncation lengths at which JavaScript returns a non-empty result; any length
        /// not listed decodes to an empty string.
        let jsNonEmpty: [String: [Int]]

        var description: String { input }
        var utf16: String { String(decoding: utf16Units, as: UTF16.self) }
    }

    static let vectors: [Vector] = [
        Vector(input: "a",
               base64: "IZA=",
               uri: "IZA",
               utf16Units: [4328, 32],
               uint8: [33, 144],
               jsNonEmpty: ["base64": [2, 3, 4], "uri": [2, 3], "utf16": [1, 2], "uint8": [2]]),
        Vector(input: "aaa",
               base64: "IYo=",
               uri: "IYo",
               utf16Units: [4325, 32, 32],
               uint8: [33, 138, 0, 0],
               jsNonEmpty: ["base64": [3, 4], "uri": [3], "utf16": [1, 2, 3], "uint8": [2, 4]]),
        Vector(input: "hello",
               base64: "BYUwNmD2Q===",
               uri: "BYUwNmD2Q",
               utf16Units: [738, 19501, 19518, 25632, 32],
               uint8: [5, 133, 48, 54, 96, 246, 64, 0],
               jsNonEmpty: ["base64": [9, 10, 11, 12], "uri": [9], "utf16": [4, 5], "uint8": [8]]),
        Vector(input: "payload-100-xx",
               base64: "A4QwngNg9iAmC0BGADM+APdQ",
               uri: "A4QwngNg9iAmC0BGADM+APdQ",
               utf16Units: [482, 3143, 16524, 3970, 336, 11553, 3104, 13150, 155, 21536, 32],
               uint8: [3, 132, 48, 158, 3, 96, 246, 32, 38, 11, 64, 70, 0, 51, 62, 0, 247, 80],
               jsNonEmpty: ["base64": [24], "uri": [24], "utf16": [10, 11], "uint8": [18]]),
    ]

    /// Truncates at the read boundary appropriate to each format.
    static func truncate(_ vector: Vector, _ format: String, _ n: Int) -> String {
        switch format {
        case "base64":
            return LZString.decompressFromBase64(input: String(vector.base64.prefix(n)))
        case "uri":
            return LZString.decompressFromEncodedURIComponent(input: String(vector.uri.prefix(n)))
        case "utf16":
            // String.prefix counts Characters, so slice by code unit instead.
            return LZString.decompressFromUTF16(input: String(decoding: Array(vector.utf16Units.prefix(n)), as: UTF16.self))
        case "uint8":
            return LZString.decompressFromUInt8Array(input: Array(vector.uint8.prefix(n)))
        default:
            return ""
        }
    }

    static func total(_ vector: Vector, _ format: String) -> Int {
        switch format {
        case "base64": return vector.base64.count
        case "uri":    return vector.uri.count
        case "utf16":  return vector.utf16Units.count
        case "uint8":  return vector.uint8.count
        default:       return 0
        }
    }

    static let formats = ["base64", "uri", "utf16", "uint8"]

    /// Known positions where this library is stricter than the JavaScript original,
    /// accepted as a documented policy decision.
    ///
    /// JavaScript treats reads past the end as zero bits and can still finish, so it
    /// decodes even when the last bit of the end-of-stream code is missing. Since #21
    /// this library fails as soon as the input is exhausted. Complete compressed output
    /// shows no difference; this is only observable on deliberately truncated input.
    static let stricterThanJavaScript: Set<String> = [
        "a/base64@2",
        "a/uri@2",
        "aaa/utf16@1",
    ]

    // MARK: - Exhaustive truncation

    /// A truncated input yields either the full text or an empty string and **never
    /// partially decoded, corrupted text**. A single trap would take down the test
    /// process, so this doubles as the safety check.
    @Test("Every truncation is safe and never partial", arguments: vectors)
    func everyTruncationIsSafeAndNeverPartial(vector: Vector) {
        for format in Self.formats {
            for n in 0...Self.total(vector, format) {
                let decoded = Self.truncate(vector, format, n)

                #expect(decoded.isEmpty || decoded == vector.input,
                        "\(vector.input)/\(format)@\(n): partial result \(decoded.debugDescription)")
            }
        }
    }

    /// Compares against the JavaScript result at every length in every format, and
    /// guarantees the only disagreements are the ones listed in stricterThanJavaScript.
    @Test("Truncation results match JavaScript, except the known differences", arguments: vectors)
    func truncationMatchesJavaScript(vector: Vector) {
        for format in Self.formats {
            let jsDecodes = Set(vector.jsNonEmpty[format] ?? [])

            for n in 0...Self.total(vector, format) {
                let key = "\(vector.input)/\(format)@\(n)"
                let decoded = Self.truncate(vector, format, n)

                if Self.stricterThanJavaScript.contains(key) {
                    #expect(decoded.isEmpty, "\(key): the known difference no longer holds (JavaScript decodes, this library fails)")
                    continue
                }

                // Where JavaScript throws (odd byte lengths for UInt8Array) there is no
                // expectation; this library contracts to return a value without trapping,
                // so agreement is not required here.
                let jsThrows = (format == "uint8" && n % 2 == 1 && n > 0)
                if jsThrows { continue }

                let expected = jsDecodes.contains(n) ? vector.input : ""
                #expect(decoded == expected, "\(key): swift=\(decoded.debugDescription) js=\(expected.debugDescription)")
            }
        }
    }

    /// Pins the smallest decodable length and the one below it by name, recording the
    /// real per-format boundary instead of a magic number such as "70 or more".
    @Test("The smallest decodable length is pinned", arguments: vectors)
    func decodingThresholdIsPinned(vector: Vector) {
        for format in Self.formats {
            guard let smallest = (vector.jsNonEmpty[format] ?? []).min() else { continue }

            let key = "\(vector.input)/\(format)@\(smallest)"
            if Self.stricterThanJavaScript.contains(key) { continue }

            #expect(Self.truncate(vector, format, smallest) == vector.input,
                    "\(key): should decode at the smallest length")

            if smallest > 0 {
                #expect(Self.truncate(vector, format, smallest - 1).isEmpty,
                        "\(vector.input)/\(format)@\(smallest - 1): one below the boundary should fail")
            }
        }
    }

    // MARK: - Data slices

    /// Empty, one-byte, odd-length and non-zero-startIndex slices. Widens coverage while
    /// keeping the #32 regression.
    @Test("Degenerate Data slices do not trap", arguments: vectors)
    func degenerateDataSlices(vector: Vector) {
        let encoded: Data = LZString.compress(input: vector.input)

        #expect(LZString.decompress(input: Data()) == "")
        #expect(LZString.decompress(input: encoded.prefix(1)) == "")

        for offset in 0...min(4, encoded.count) {
            var packet = Data(repeating: 0x5A, count: offset)
            packet.append(encoded)
            let slice = packet.dropFirst(offset)

            #expect(slice.startIndex == offset)
            #expect(LZString.decompress(input: slice) == vector.input)

            // Truncating the slice to every length must not trap either.
            for length in 0...encoded.count {
                let truncated = slice.prefix(length)
                let decoded = LZString.decompress(input: truncated)
                #expect(decoded.isEmpty || decoded == vector.input,
                        "offset=\(offset) length=\(length): partial result \(decoded.debugDescription)")
            }
        }

        // Odd byte lengths.
        for odd in stride(from: 1, to: encoded.count, by: 2) {
            let decoded = LZString.decompress(input: encoded.prefix(odd))
            #expect(decoded.isEmpty || decoded == vector.input)
        }
    }

    // MARK: - Deterministic mutations

    /// Altered initial tags, dictionary codes and terminal bits, characters outside the
    /// alphabet, and low UTF16 units. **Not every mutation is invalid** — some encode
    /// different valid text — so this only requires that nothing traps or hangs.
    @Test("Deterministic mutations neither trap nor hang", arguments: vectors)
    func boundedDeterministicMutations(vector: Vector) {
        // Inject characters outside the Base64 / URI alphabet at various positions.
        for (index, intruder) in ["あ", "\u{0}", "~", "\u{FFFF}", " ", "%"].enumerated() {
            let position = vector.base64.isEmpty ? 0 : index % vector.base64.count
            var mutated = Array(vector.base64)
            if !mutated.isEmpty { mutated[position] = Character(intruder) }
            _ = LZString.decompressFromBase64(input: String(mutated))

            var mutatedURI = Array(vector.uri)
            if !mutatedURI.isEmpty { mutatedURI[position % max(mutatedURI.count, 1)] = Character(intruder) }
            _ = LZString.decompressFromEncodedURIComponent(input: String(mutatedURI))
        }

        // Inject low code units into the UTF16 format, where nextValue can go negative.
        for unit in [UInt16(0), 1, 31] {
            var units = vector.utf16Units
            if !units.isEmpty {
                units[0] = unit
                _ = LZString.decompressFromUTF16(input: String(decoding: units, as: UTF16.self))
            }
        }

        // Flip the lowest bit of each byte, which includes altering the terminal bits.
        for index in vector.uint8.indices {
            var bytes = vector.uint8
            bytes[index] ^= 0x01
            let decoded = LZString.decompressFromUInt8Array(input: bytes)
            // The result may be different valid text, so its content is not asserted.
            _ = decoded
        }

        // Alter the initial tag.
        if !vector.uint8.isEmpty {
            for pattern in [UInt8(0x00), 0xFF, 0x80] {
                var bytes = vector.uint8
                bytes[0] = pattern
                _ = LZString.decompressFromUInt8Array(input: bytes)
            }
        }
    }

    // MARK: - Protecting valid input

    /// Guarantees that valid input ending exactly on a boundary, and URI input whose '+'
    /// became a space, are still accepted — hardening must not reject them.
    @Test("Normalisation of valid input still works", arguments: vectors)
    func validInputNormalisationIsPreserved(vector: Vector) {
        #expect(LZString.decompressFromBase64(input: vector.base64) == vector.input)
        #expect(LZString.decompressFromEncodedURIComponent(input: vector.uri) == vector.input)
        #expect(LZString.decompressFromUTF16(input: vector.utf16) == vector.input)
        #expect(LZString.decompressFromUInt8Array(input: vector.uint8) == vector.input)
        #expect(LZString.decompress(input: LZString.compress(input: vector.input) as Data) == vector.input)

        // The path where a URL decoder turns '+' into a space.
        let spaced = vector.uri.replacingOccurrences(of: "+", with: " ")
        #expect(LZString.decompressFromEncodedURIComponent(input: spaced) == vector.input,
                "\(vector.input): a URI with '+' replaced by a space failed to decode")
    }

    /// Exercises the space-replacement path with a payload that actually contains '+';
    /// with an input that has none, the replacement does nothing and protects nothing.
    @Test("A URI payload containing '+' round-trips through a space")
    func uriPayloadContainingPlusRoundTripsThroughSpace() throws {
        let vector = try #require(Self.vectors.first { $0.uri.contains("+") })

        #expect(vector.uri.contains("+"), "this vector must contain '+'")

        let spaced = vector.uri.replacingOccurrences(of: "+", with: " ")
        #expect(spaced != vector.uri)
        #expect(LZString.decompressFromEncodedURIComponent(input: spaced) == vector.input)
    }
}
