import Testing
import Foundation
@testable import LZString

/// Issue #41 — differential tests against the original JavaScript implementation at dictionary
/// bit-width transitions. A Swift-only round trip can miss a bug shared by the
/// compressor and the decompressor, so the reference acts as an independent oracle.
///
/// The corpus is committed, so a normal test run needs neither Node nor network.
/// Regenerate with the script under `Scripts/`, which pins the reference version,
/// its sha256, and the input-generation seed.
///
/// **The transitions are located by instrumenting the reference implementation.**
/// Input length and dictionary size do not correspond, so they are never inferred
/// from length.
@Suite("JavaScript differential")
struct JavaScriptDifferentialTests {
    struct Corpus: Decodable {
        let seed: Int
        let referenceVersion: String
        let referenceSha256: String
        let bases: [String: String]
        let exercised: [String: [Int]]
        let cases: [Case]
    }

    struct Case: Decodable, Sendable, CustomStringConvertible {
        let id: String
        let baseId: String
        let prefixLength: Int
        let note: String
        let width: Int
        let position: String
        let base64: String
        let uri: String
        let utf16Hex: String
        let uint8Hex: String
        let inputUtf16Hex: String

        var description: String { id }
    }

    static let corpus: Corpus = {
        // A load failure means this was not run from the package root.
        let url = URL(fileURLWithPath: "Tests/Resources/js_differential.json")
        return try! JSONDecoder().decode(Corpus.self, from: Data(contentsOf: url))
    }()

    static let cases: [Case] = corpus.cases

    // MARK: - Helpers

    static func units(fromHex hex: String) -> [UInt16] {
        stride(from: 0, to: hex.count, by: 4).map { offset in
            let start = hex.index(hex.startIndex, offsetBy: offset)
            let end = hex.index(start, offsetBy: 4)
            return UInt16(hex[start..<end], radix: 16)!
        }
    }

    static func bytes(fromHex hex: String) -> [UInt8] {
        stride(from: 0, to: hex.count, by: 2).map { offset in
            let start = hex.index(hex.startIndex, offsetBy: offset)
            let end = hex.index(start, offsetBy: 2)
            return UInt8(hex[start..<end], radix: 16)!
        }
    }

    /// Slices by UTF-16 code unit, exactly as the reference implementation does.
    static func input(for testCase: Case) -> String {
        let base = corpus.bases[testCase.baseId]!
        return String(decoding: Array(base.utf16.prefix(testCase.prefixLength)), as: UTF16.self)
    }

    /// Returns the comparison result together with the diagnostic shown on failure
    /// (seed, case, format and the first differing position).
    ///
    /// The comment argument of `#expect` is an autoclosure evaluated only on failure.
    /// Building the diagnostic there would leave those lines unexecuted and missing from
    /// coverage, so the check and the diagnostic are **always evaluated** together.
    static func compare<T: Equatable>(_ actual: [T], _ expected: [T], case testCase: Case, format: String) -> (Bool, Comment) {
        let limit = min(actual.count, expected.count)
        var index = 0
        while index < limit, actual[index] == expected[index] { index += 1 }

        let matched = actual.count == expected.count && index == limit
        let actualValue = index < actual.count ? "\(actual[index])" : "<end>"
        let expectedValue = index < expected.count ? "\(expected[index])" : "<end>"

        let comment = Comment(rawValue: """
            seed=\(corpus.seed) case=\(testCase.id) format=\(format) \
            (growth to numBits \(testCase.width), position \(testCase.position): \(testCase.note))
            first difference at index \(index) — swift=\(actualValue) js=\(expectedValue) \
            (swift \(actual.count) elements / js \(expected.count) elements)
            """)

        return (matched, comment)
    }

    // MARK: - Corpus self-checks

    @Test("Corpus provenance matches what is recorded")
    func corpusMetadataIsPinned() {
        #expect(Self.corpus.referenceVersion == "1.5.0")
        #expect(Self.corpus.referenceSha256 == "550034b821027008776cb9bcd1700bb5d31e8b3de224cb130fc966a75dab0e5e")
        #expect(Self.corpus.seed == 20261026)
        #expect(!Self.cases.isEmpty)
    }

    /// Pins which numBits transitions this suite actually exercises.
    /// Documents which width transitions this suite actually exercises.
    @Test("The exercised dictionary widths match what is recorded")
    func exercisedWidthsAreDocumented() {
        #expect(Self.corpus.exercised["repeatedPattern"] == [4, 5, 6, 7])
        #expect(Self.corpus.exercised["jsonLike"] == [4, 5, 6, 7, 8, 9, 10])
        #expect(Self.corpus.exercised["highEntropy"] == [4, 5, 6, 7, 8, 9, 10, 11])

        // Every width must have the before / at / after positions.
        for width in 4...11 {
            let positions = Set(Self.cases.filter { $0.width == width }.map(\.position))
            #expect(positions.isSuperset(of: ["before", "at", "after"]),
                    "numBits \(width): missing before/at/after (\(positions.sorted()))")
        }
    }

    /// Guarantees the slice taken on the Swift side has the same UTF-16 units as the
    /// string the JavaScript side used when generating the expectations.
    @Test("The reconstructed input matches the reference", arguments: cases)
    func reconstructedInputMatchesReference(testCase: Case) {
        let actual = Array(Self.input(for: testCase).utf16)
        let expected = Self.units(fromHex: testCase.inputUtf16Hex)

        let (resultInputOK, resultInputComment) = Self.compare(actual, expected, case: testCase, format: "input")
        #expect(resultInputOK, resultInputComment)
    }

    // MARK: - Compression differential

    @Test("Compressed output matches JavaScript in every format", arguments: cases)
    func compressionMatchesJavaScript(testCase: Case) {
        let input = Self.input(for: testCase)

        let base64 = LZString.compressToBase64(input: input)
        let (base64OK, base64Comment) = Self.compare(Array(base64), Array(testCase.base64), case: testCase, format: "base64")
        #expect(base64OK, base64Comment)

        let uri = LZString.compressToEncodedURIComponent(input: input)
        let (uriOK, uriComment) = Self.compare(Array(uri), Array(testCase.uri), case: testCase, format: "uri")
        #expect(uriOK, uriComment)

        let utf16 = Array(LZString.compressToUTF16(input: input).utf16)
        let expectedUTF16 = Self.units(fromHex: testCase.utf16Hex)
        let (resultUtf16OK, resultUtf16Comment) = Self.compare(utf16, expectedUTF16, case: testCase, format: "utf16")
        #expect(resultUtf16OK, resultUtf16Comment)

        let uint8 = LZString.compressToUInt8Array(input: input)
        let expectedUInt8 = Self.bytes(fromHex: testCase.uint8Hex)
        let (resultUint8OK, resultUint8Comment) = Self.compare(uint8, expectedUInt8, case: testCase, format: "uint8Array")
        #expect(resultUint8OK, resultUint8Comment)

        // Data keeps little-endian byte order, so each pair of the JavaScript
        // UInt8Array is swapped before comparing.
        var expectedData = [UInt8]()
        for i in stride(from: 0, to: expectedUInt8.count, by: 2) {
            expectedData.append(expectedUInt8[i + 1])
            expectedData.append(expectedUInt8[i])
        }
        let data = [UInt8](LZString.compress(input: input) as Data)
        let (resultDataOK, resultDataComment) = Self.compare(data, expectedData, case: testCase, format: "data")
        #expect(resultDataOK, resultDataComment)
    }

    // MARK: - Decompression differential

    /// Decompresses JavaScript-produced payloads and checks exact UTF-16 code-unit
    /// equality with the input; canonical equivalence is not enough (issue #40).
    @Test("JavaScript-produced payloads decode exactly", arguments: cases)
    func decodingJavaScriptPayloadsIsExact(testCase: Case) {
        let expected = Self.units(fromHex: testCase.inputUtf16Hex)

        let fromBase64 = Array(LZString.decompressFromBase64(input: testCase.base64).utf16)
        let (resultDecodebase64OK, resultDecodebase64Comment) = Self.compare(fromBase64, expected, case: testCase, format: "decode/base64")
        #expect(resultDecodebase64OK, resultDecodebase64Comment)

        let fromURI = Array(LZString.decompressFromEncodedURIComponent(input: testCase.uri).utf16)
        let (resultDecodeuriOK, resultDecodeuriComment) = Self.compare(fromURI, expected, case: testCase, format: "decode/uri")
        #expect(resultDecodeuriOK, resultDecodeuriComment)

        let utf16Payload = String(decoding: Self.units(fromHex: testCase.utf16Hex), as: UTF16.self)
        let fromUTF16 = Array(LZString.decompressFromUTF16(input: utf16Payload).utf16)
        let (resultDecodeutf16OK, resultDecodeutf16Comment) = Self.compare(fromUTF16, expected, case: testCase, format: "decode/utf16")
        #expect(resultDecodeutf16OK, resultDecodeutf16Comment)

        let fromUInt8 = Array(LZString.decompressFromUInt8Array(input: Self.bytes(fromHex: testCase.uint8Hex)).utf16)
        let (resultDecodeuint8OK, resultDecodeuint8Comment) = Self.compare(fromUInt8, expected, case: testCase, format: "decode/uint8Array")
        #expect(resultDecodeuint8OK, resultDecodeuint8Comment)
    }
}
