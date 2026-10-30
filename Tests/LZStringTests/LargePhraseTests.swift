import Testing
import Foundation
@testable import LZString

/// Issue #34 — differential tests against the JavaScript implementation for inputs long
/// enough to build deep dictionaries and long phrases.
///
/// `JavaScriptDifferentialTests` works from prefixes of three roughly 2 KiB bases, so the
/// phrases it reaches stay short. The compressor identifies a phrase by its prefix's
/// dictionary code, and that representation only has room to diverge from a phrase-keyed
/// lookup once phrases grow long, which is what these cases exercise.
///
/// The inputs are built here from `unit` and `count` rather than committed: 1 Mi UTF-16
/// units of `"a"` compress to about 2.3 KiB of Base64, so only the **expectations** need to
/// be stored. Regenerate them with the script under `Scripts/`, which pins the reference
/// version and its sha256. **Do not regenerate them to make a failing test pass.**
@Suite("Large repeated phrases")
struct LargePhraseTests {
    struct Corpus: Decodable {
        let referenceVersion: String
        let referenceSha256: String
        let cases: [Case]
    }

    struct Case: Decodable, Sendable, CustomStringConvertible {
        let id: String
        let unit: String
        let count: Int
        let note: String
        let inputUtf16Units: Int
        let base64: String
        let uri: String
        let utf16Hex: String
        let uint8Hex: String

        var description: String { id }

        /// The input is rebuilt rather than stored; the fixture records the length so a
        /// mismatch is reported as such instead of as a compression failure.
        var input: String { String(repeating: unit, count: count) }
    }

    static let corpus: Corpus = {
        // A load failure means this was not run from the package root.
        let url = URL(fileURLWithPath: "Tests/Resources/js_large_phrases.json")
        return try! JSONDecoder().decode(Corpus.self, from: Data(contentsOf: url))
    }()

    static let cases: [Case] = corpus.cases

    static func units(fromHex hex: String) -> [UInt16] {
        stride(from: 0, to: hex.count, by: 4).map { offset in
            let start = hex.index(hex.startIndex, offsetBy: offset)
            return UInt16(hex[start..<hex.index(start, offsetBy: 4)], radix: 16)!
        }
    }

    static func bytes(fromHex hex: String) -> [UInt8] {
        stride(from: 0, to: hex.count, by: 2).map { offset in
            let start = hex.index(hex.startIndex, offsetBy: offset)
            return UInt8(hex[start..<hex.index(start, offsetBy: 2)], radix: 16)!
        }
    }

    @Test("Corpus provenance matches what is recorded")
    func corpusMetadataIsPinned() {
        #expect(Self.corpus.referenceVersion == "1.5.0")
        #expect(Self.corpus.referenceSha256 == "550034b821027008776cb9bcd1700bb5d31e8b3de224cb130fc966a75dab0e5e")
        #expect(Self.cases.count == 9)
        // The largest case must actually be large, or this suite proves nothing about
        // long phrases.
        #expect(Self.cases.map(\.inputUtf16Units).max() == 1_048_576)
    }

    /// Guarantees the input rebuilt here has the length the reference measured, so a
    /// failure below is a compression difference rather than a different input.
    @Test("The rebuilt input has the recorded length", arguments: cases)
    func rebuiltInputLengthMatches(testCase: Case) {
        #expect(testCase.input.utf16.count == testCase.inputUtf16Units,
                "\(testCase.id): rebuilt \(testCase.input.utf16.count) units, fixture records \(testCase.inputUtf16Units)")
    }

    @Test("Compressed output matches JavaScript in every format", arguments: cases)
    func compressionMatchesJavaScript(testCase: Case) {
        let input = testCase.input

        #expect(LZString.compressToBase64(input: input) == testCase.base64, "\(testCase.id): base64")
        #expect(LZString.compressToEncodedURIComponent(input: input) == testCase.uri, "\(testCase.id): uri")
        #expect(Array(LZString.compressToUTF16(input: input).utf16) == Self.units(fromHex: testCase.utf16Hex),
                "\(testCase.id): utf16")

        let expectedUInt8 = Self.bytes(fromHex: testCase.uint8Hex)
        #expect(LZString.compressToUInt8Array(input: input) == expectedUInt8, "\(testCase.id): uint8Array")

        // Data keeps little-endian byte order, so each pair of the JavaScript UInt8Array is
        // swapped before comparing.
        var expectedData = [UInt8]()
        expectedData.reserveCapacity(expectedUInt8.count)
        for i in stride(from: 0, to: expectedUInt8.count, by: 2) {
            expectedData.append(expectedUInt8[i + 1])
            expectedData.append(expectedUInt8[i])
        }
        #expect([UInt8](LZString.compress(input: input) as Data) == expectedData, "\(testCase.id): data")
    }

    /// Decompresses the JavaScript-produced payloads and requires exact UTF-16 code-unit
    /// equality with the input.
    @Test("JavaScript-produced payloads decode exactly", arguments: cases)
    func decodingJavaScriptPayloadsIsExact(testCase: Case) {
        let expected = Array(testCase.input.utf16)

        #expect(Array(LZString.decompressFromBase64(input: testCase.base64).utf16) == expected,
                "\(testCase.id): decode/base64")
        #expect(Array(LZString.decompressFromEncodedURIComponent(input: testCase.uri).utf16) == expected,
                "\(testCase.id): decode/uri")

        let utf16Payload = String(decoding: Self.units(fromHex: testCase.utf16Hex), as: UTF16.self)
        #expect(Array(LZString.decompressFromUTF16(input: utf16Payload).utf16) == expected,
                "\(testCase.id): decode/utf16")
        #expect(Array(LZString.decompressFromUInt8Array(input: Self.bytes(fromHex: testCase.uint8Hex)).utf16) == expected,
                "\(testCase.id): decode/uint8Array")
    }
}
