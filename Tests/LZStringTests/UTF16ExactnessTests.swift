import Testing
import Foundation
@testable import LZString

/// Issue #40 — exact UTF-16 code-unit equality and Unicode boundary compatibility.
///
///     "\u{00E9}" == "e\u{0301}"                              // true
///     Array("\u{00E9}".utf16) == Array("e\u{0301}".utf16)     // false
///
/// Swift's `String ==` is canonical equivalence, so a normalizing implementation would
/// still pass a round-trip test. What this library promises is code-unit and byte
/// compatibility with the JavaScript implementation, not visually equal text, so this
/// suite compares `Array(decoded.utf16) == Array(input.utf16)` throughout.
///
/// Expected values are pinned outputs from lz-string 1.5.0 under Node.
@Suite("Exact UTF-16 and Unicode boundaries")
struct UTF16ExactnessTests {
    struct Vector: Sendable, CustomStringConvertible {
        let name: String
        let input: String
        let utf16: [UInt16]
        let base64: String
        let uri: String
        let utf16Units: [UInt16]
        let uint8: [UInt8]

        var description: String { name }
    }

    static let vectors: [Vector] = [
        Vector(name: "nfcPrecomposedE",
               input: "\u{E9}",
               utf16: [233],
               base64: "JdA=",
               uri: "JdA",
               utf16Units: [4872, 32],
               uint8: [37, 208]),
        Vector(name: "nfdDecomposedE",
               input: "\u{65}\u{301}",
               utf16: [101, 769],
               base64: "KaQGAg==",
               uri: "KaQGAg",
               utf16Units: [5362, 416, 16416, 32],
               uint8: [41, 164, 6, 2, 0, 0]),
        Vector(name: "nfcHangulGak",
               input: "\u{AC01}",
               utf16: [44033],
               base64: "oA1Q",
               uri: "oA1Q",
               utf16Units: [20518, 21536, 32],
               uint8: [160, 13, 80, 0]),
        Vector(name: "nfdHangulGak",
               input: "\u{1100}\u{1161}\u{11A8}",
               utf16: [4352, 4449, 4520],
               base64: "gCIkNEQViEA=",
               uri: "gCIkNEQViEA",
               utf16Units: [16433, 2349, 2210, 22692, 32, 32],
               uint8: [128, 34, 36, 52, 68, 21, 136, 64]),
        Vector(name: "combiningMarksOnly",
               input: "\u{301}\u{302}\u{303}",
               utf16: [769, 770, 771],
               base64: "oDAiBgTAwEA=",
               uri: "oDAiBgTAwEA",
               utf16Units: [20536, 2209, 16568, 3108, 32, 32],
               uint8: [160, 48, 34, 6, 4, 192, 192, 64]),
        Vector(name: "zwjFamilyEmoji",
               input: "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}",
               utf16: [55357, 56424, 8205, 55357, 56425, 8205, 55357, 56423],
               base64: "rwbgsdywBMiWOxjmO0A=",
               uri: "rwbgsdywBMiWOxjmO0A",
               utf16Units: [22435, 14412, 15286, 108, 17617, 27779, 19606, 16416, 32],
               uint8: [175, 6, 224, 177, 220, 176, 4, 200, 150, 59, 24, 230, 59, 64]),
        Vector(name: "variationSelectorHeart",
               input: "\u{2764}\u{FE0F}",
               utf16: [10084, 65039],
               base64: "ibkng/o=",
               uri: "ibkng-o",
               utf16Units: [17660, 18944, 32608, 32],
               uint8: [137, 185, 39, 131, 250, 0]),
        Vector(name: "nullCodeUnit",
               input: "\u{0}",
               utf16: [0],
               base64: "ABA=",
               uri: "ABA",
               utf16Units: [40, 32],
               uint8: [0, 16]),
        Vector(name: "asciiBoundary7F",
               input: "\u{7F}",
               utf16: [127],
               base64: "P5A=",
               uri: "P5A",
               utf16Units: [8168, 32],
               uint8: [63, 144]),
        Vector(name: "latin1Boundary80",
               input: "\u{80}",
               utf16: [128],
               base64: "AFA=",
               uri: "AFA",
               utf16Units: [72, 32],
               uint8: [0, 80]),
        Vector(name: "literalBoundaryFF",
               input: "\u{FF}",
               utf16: [255],
               base64: "P9A=",
               uri: "P9A",
               utf16Units: [8200, 32],
               uint8: [63, 208]),
        Vector(name: "literalBoundary0100",
               input: "\u{100}",
               utf16: [256],
               base64: "gCAQ",
               uri: "gCAQ",
               utf16Units: [16432, 1056, 32],
               uint8: [128, 32, 16, 0]),
        Vector(name: "surrogateBoundaryD7FF",
               input: "\u{D7FF}",
               utf16: [55295],
               base64: "v/rQ",
               uri: "v-rQ",
               utf16Units: [24605, 13344, 32],
               uint8: [191, 250, 208, 0]),
        Vector(name: "surrogateBoundaryE000",
               input: "\u{E000}",
               utf16: [57344],
               base64: "gAHQ",
               uri: "gAHQ",
               utf16Units: [16416, 29728, 32],
               uint8: [128, 1, 208, 0]),
        Vector(name: "bmpMaxFFFF",
               input: "\u{FFFF}",
               utf16: [65535],
               base64: "v//Q",
               uri: "v--Q",
               utf16Units: [24607, 29728, 32],
               uint8: [191, 255, 208, 0]),
        Vector(name: "supplementaryMin10000",
               input: "\u{10000}",
               utf16: [55296, 56320],
               base64: "gAbgAdo=",
               uri: "gAbgAdo",
               utf16Units: [16419, 14368, 15200, 32],
               uint8: [128, 6, 224, 1, 218, 0]),
        Vector(name: "supplementaryMax10FFFF",
               input: "\u{10FFFF}",
               utf16: [56319, 57343],
               base64: "v/bn/9o=",
               uri: "v-bn-9o",
               utf16Units: [24603, 14879, 31584, 32],
               uint8: [191, 246, 231, 255, 218, 0]),
        Vector(name: "mixedLiteralWidths",
               input: "\u{41}\u{FF}\u{100}\u{41}\u{FF}\u{100}",
               utf16: [65, 255, 256, 65, 255, 256],
               base64: "IIf8AICmQ===",
               uri: "IIf8AICmQ",
               utf16Units: [4195, 32544, 4148, 25632, 32],
               uint8: [32, 135, 252, 0, 128, 166, 64, 0]),
        Vector(name: "repeatedAcrossBoundary",
               input: "\u{FF}\u{100}\u{FF}\u{100}\u{FF}\u{100}\u{FF}\u{100}",
               utf16: [255, 256, 255, 256, 255, 256, 255, 256],
               base64: "P+AEBeSA",
               uri: "P+AEBeSA",
               utf16Units: [8208, 289, 15536, 32],
               uint8: [63, 224, 4, 5, 228, 128]),
        Vector(name: "newLiteralAtEnd",
               input: "\u{41}\u{41}\u{41}\u{10FFFF}",
               utf16: [65, 65, 65, 56319, 57343],
               base64: "IIz/25//aA==",
               uri: "IIz-25--aA",
               utf16Units: [4198, 16406, 29727, 30368, 32],
               uint8: [32, 140, 255, 219, 159, 255, 104, 0]),
        Vector(name: "newWideLiteralAtEnd",
               input: "\u{41}\u{41}\u{41}\u{100}",
               utf16: [65, 65, 65, 256],
               base64: "IIwAgE==",
               uri: "IIwAgE",
               utf16Units: [4198, 64, 2080, 32],
               uint8: [32, 140, 0, 128, 64, 0]),
        Vector(name: "asciiThenSupplementary",
               input: "\u{61}\u{62}\u{1F97A}\u{63}",
               utf16: [97, 98, 55358, 56698, 99],
               base64: "IYI0fBuF67DGQ===",
               uri: "IYI0fBuF67DGQ",
               utf16Units: [4321, 3391, 912, 24283, 1618, 32, 32],
               uint8: [33, 130, 52, 124, 27, 133, 235, 176, 198, 64]),
    ]

    /// Compares exact UTF-16 code units rather than canonical equivalence, and reports
    /// the first differing position when they disagree.
    static func exactUTF16(_ actual: String, _ expected: [UInt16], _ label: String) -> (Bool, Comment) {
        let units = Array(actual.utf16)

        if units == expected {
            return (true, "")
        }

        let limit = min(units.count, expected.count)
        var index = 0
        while index < limit, units[index] == expected[index] { index += 1 }

        let actualUnit = index < units.count ? String(units[index], radix: 16, uppercase: true) : "<end>"
        let expectedUnit = index < expected.count ? String(expected[index], radix: 16, uppercase: true) : "<end>"

        return (false, Comment(rawValue: "\(label): first difference at index \(index) — actual U+\(actualUnit) / expected U+\(expectedUnit) "
            + "(actual \(units.count) units, expected \(expected.count) units)"))
    }

    /// Guarantees the Swift literal matches the string the JavaScript side used when the
    /// expectations were generated. Everything else is meaningless if this drifts.
    @Test("Input matches the JavaScript corpus code unit for code unit", arguments: vectors)
    func inputMatchesPinnedCodeUnits(vector: Vector) {
        let (ok, comment) = Self.exactUTF16(vector.input, vector.utf16, vector.name)
        #expect(ok, comment)
    }

    @Test("Compressed output matches JavaScript in every format", arguments: vectors)
    func compressedOutputMatchesJavaScript(vector: Vector) {
        #expect(LZString.compressToBase64(input: vector.input) == vector.base64, "\(vector.name): base64")
        #expect(LZString.compressToEncodedURIComponent(input: vector.input) == vector.uri, "\(vector.name): uri")
        #expect(Array(LZString.compressToUTF16(input: vector.input).utf16) == vector.utf16Units, "\(vector.name): utf16")
        #expect(LZString.compressToUInt8Array(input: vector.input) == vector.uint8, "\(vector.name): uint8Array")

        // Data keeps little-endian byte order, so each pair is swapped relative to the
        // JavaScript UInt8Array.
        let data: Data = LZString.compress(input: vector.input)
        var swapped = [UInt8]()
        for i in stride(from: 0, to: vector.uint8.count, by: 2) {
            swapped.append(vector.uint8[i + 1])
            swapped.append(vector.uint8[i])
        }
        #expect([UInt8](data) == swapped, "\(vector.name): data")
    }

    /// Compares the decoded result against the input by code unit for every lossless
    /// format. An implementation that normalises, or that identifies phrases by
    /// `Character`, fails here.
    @Test("Decoded output equals the input code unit for code unit", arguments: vectors)
    func decodedUnitsAreExactlyEqual(vector: Vector) {
        let decoders: [(String, String)] = [
            ("base64", LZString.decompressFromBase64(input: vector.base64)),
            ("uri", LZString.decompressFromEncodedURIComponent(input: vector.uri)),
            ("utf16", LZString.decompressFromUTF16(input: LZString.compressToUTF16(input: vector.input))),
            ("uint8Array", LZString.decompressFromUInt8Array(input: vector.uint8)),
            ("data", LZString.decompress(input: LZString.compress(input: vector.input) as Data)),
        ]

        for (format, decoded) in decoders {
            let (ok, comment) = Self.exactUTF16(decoded, vector.utf16, "\(vector.name)/\(format)")
            #expect(ok, comment)
        }
    }

    /// Pins that an NFC/NFD pair — indistinguishable under canonical equivalence —
    /// compresses to different payloads and each returns its own code units.
    /// An implementation that normalised its input would make the two payloads equal.
    @Test("NFC and NFD stay distinct through a round trip", arguments: [
        ("nfcPrecomposedE", "nfdDecomposedE"),
        ("nfcHangulGak", "nfdHangulGak"),
    ])
    func canonicallyEquivalentFormsStayDistinct(nfcName: String, nfdName: String) throws {
        let nfc = try #require(Self.vectors.first { $0.name == nfcName })
        let nfd = try #require(Self.vectors.first { $0.name == nfdName })

        // Make it explicit that Swift's == considers this pair equal.
        #expect(nfc.input == nfd.input)
        #expect(Array(nfc.input.utf16) != Array(nfd.input.utf16))

        // The compressed payloads must differ.
        #expect(nfc.base64 != nfd.base64)

        // Each decodes back to its own code units.
        let (nfcOK, nfcComment) = Self.exactUTF16(LZString.decompressFromBase64(input: nfc.base64), nfc.utf16, nfcName)
        #expect(nfcOK, nfcComment)

        let (nfdOK, nfdComment) = Self.exactUTF16(LZString.decompressFromBase64(input: nfd.base64), nfd.utf16, nfdName)
        #expect(nfdOK, nfdComment)
    }
}
