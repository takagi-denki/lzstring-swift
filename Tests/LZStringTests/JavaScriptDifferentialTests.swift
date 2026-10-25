import Testing
import Foundation
@testable import LZString

/// Issue #41 — 辞書ビット幅 (numBits) の成長境界における JS 差分テスト。
///
/// 既存のゴールデンファイルはラテン文字 1 段落のみで、どの `numBits` 遷移を
/// 踏んでいるかが記録されていなかった。Swift だけの往復テストは、圧縮と展開に
/// 共通する誤りを見逃す。そこで本家 JavaScript 実装を独立したオラクルとして使う。
///
/// Differential tests against the original JavaScript implementation at dictionary
/// bit-width transitions. A Swift-only round trip can miss a bug shared by the
/// compressor and the decompressor, so the reference acts as an independent oracle.
///
/// コーパスは `Tests/Resources/js_differential.json` にコミット済みで、
/// 通常の `swift test` は Node もネットワークも必要としない。
/// 再生成は `Scripts/generate-js-differential-fixture.js`（参照実装のバージョンと
/// sha256、入力生成の seed を固定）。
///
/// The corpus is committed, so a normal test run needs neither Node nor network.
/// Regenerate with the script under `Scripts/`, which pins the reference version,
/// its sha256, and the input-generation seed.
///
/// **境界は参照実装側を計装して特定している。** 入力長と辞書サイズは一致しないため、
/// 長さから推測はしない。
@Suite("JS 差分テスト / JavaScript differential")
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
        let url = URL(fileURLWithPath: "Tests/Resources/js_differential.json")
        guard let data = try? Data(contentsOf: url) else {
            fatalError("Tests/Resources/js_differential.json を読めません。swift test はパッケージルートから実行してください。")
        }
        return try! JSONDecoder().decode(Corpus.self, from: data)
    }()

    static let cases: [Case] = corpus.cases

    // MARK: - 補助

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

    /// 参照実装と同じく UTF-16 コードユニット単位で切り出す。
    static func input(for testCase: Case) -> String {
        let base = corpus.bases[testCase.baseId]!
        return String(decoding: Array(base.utf16.prefix(testCase.prefixLength)), as: UTF16.self)
    }

    /// 失敗時に seed・ケース・形式・最初に相違した位置を報告する。
    static func diagnose<T: Equatable>(_ actual: [T], _ expected: [T], case testCase: Case, format: String) -> Comment {
        let limit = min(actual.count, expected.count)
        var index = 0
        while index < limit, actual[index] == expected[index] { index += 1 }

        let actualValue = index < actual.count ? "\(actual[index])" : "<end>"
        let expectedValue = index < expected.count ? "\(expected[index])" : "<end>"

        return Comment(rawValue: """
            seed=\(corpus.seed) case=\(testCase.id) format=\(format) \
            (numBits \(testCase.width) への成長 \(testCase.position), \(testCase.note))
            最初の相違: index \(index) — swift=\(actualValue) js=\(expectedValue) \
            (swift \(actual.count) 要素 / js \(expected.count) 要素)
            """)
    }

    // MARK: - コーパスの自己検証

    @Test("コーパスの前提が記録どおりである")
    func corpusMetadataIsPinned() {
        #expect(Self.corpus.referenceVersion == "1.5.0")
        #expect(Self.corpus.referenceSha256 == "550034b821027008776cb9bcd1700bb5d31e8b3de224cb130fc966a75dab0e5e")
        #expect(Self.corpus.seed == 20261026)
        #expect(!Self.cases.isEmpty)
    }

    /// 実際に検証している numBits 遷移を記録として固定する。
    /// Documents which width transitions this suite actually exercises.
    @Test("検証対象の辞書ビット幅が記録どおりである")
    func exercisedWidthsAreDocumented() {
        #expect(Self.corpus.exercised["repeatedPattern"] == [4, 5, 6, 7])
        #expect(Self.corpus.exercised["jsonLike"] == [4, 5, 6, 7, 8, 9, 10])
        #expect(Self.corpus.exercised["highEntropy"] == [4, 5, 6, 7, 8, 9, 10, 11])

        // 各幅について 直前 / 時点 / 直後 が揃っていること。
        for width in 4...11 {
            let positions = Set(Self.cases.filter { $0.width == width }.map(\.position))
            #expect(positions.isSuperset(of: ["before", "at", "after"]),
                    "numBits \(width): 直前/時点/直後 が揃っていない (\(positions.sorted()))")
        }
    }

    /// Swift 側で切り出した入力が、JS 側で期待値を生成したときと同一の
    /// UTF-16 列であることを先に保証する。
    @Test("切り出した入力が JS 側と同一である", arguments: cases)
    func reconstructedInputMatchesReference(testCase: Case) {
        let actual = Array(Self.input(for: testCase).utf16)
        let expected = Self.units(fromHex: testCase.inputUtf16Hex)

        #expect(actual == expected, Self.diagnose(actual, expected, case: testCase, format: "input"))
    }

    // MARK: - 圧縮の差分

    @Test("圧縮結果が全形式で JS と一致する", arguments: cases)
    func compressionMatchesJavaScript(testCase: Case) {
        let input = Self.input(for: testCase)

        let base64 = LZString.compressToBase64(input: input)
        #expect(base64 == testCase.base64,
                Self.diagnose(Array(base64), Array(testCase.base64), case: testCase, format: "base64"))

        let uri = LZString.compressToEncodedURIComponent(input: input)
        #expect(uri == testCase.uri,
                Self.diagnose(Array(uri), Array(testCase.uri), case: testCase, format: "uri"))

        let utf16 = Array(LZString.compressToUTF16(input: input).utf16)
        let expectedUTF16 = Self.units(fromHex: testCase.utf16Hex)
        #expect(utf16 == expectedUTF16, Self.diagnose(utf16, expectedUTF16, case: testCase, format: "utf16"))

        let uint8 = LZString.compressToUInt8Array(input: input)
        let expectedUInt8 = Self.bytes(fromHex: testCase.uint8Hex)
        #expect(uint8 == expectedUInt8, Self.diagnose(uint8, expectedUInt8, case: testCase, format: "uint8Array"))

        // Data はリトルエンディアンのバイト順を保つため、JS の UInt8Array を
        // 2 バイトごとに入れ替えて比較する。
        var expectedData = [UInt8]()
        for i in stride(from: 0, to: expectedUInt8.count, by: 2) {
            expectedData.append(expectedUInt8[i + 1])
            expectedData.append(expectedUInt8[i])
        }
        let data = [UInt8](LZString.compress(input: input) as Data)
        #expect(data == expectedData, Self.diagnose(data, expectedData, case: testCase, format: "data"))
    }

    // MARK: - 展開の差分

    /// JS が生成したペイロードを Swift で展開し、UTF-16 コードユニット単位で
    /// 入力と完全一致することを確認する（正規等価では不十分、issue #40）。
    @Test("JS が生成したペイロードを展開して完全一致する", arguments: cases)
    func decodingJavaScriptPayloadsIsExact(testCase: Case) {
        let expected = Self.units(fromHex: testCase.inputUtf16Hex)

        let fromBase64 = Array(LZString.decompressFromBase64(input: testCase.base64).utf16)
        #expect(fromBase64 == expected, Self.diagnose(fromBase64, expected, case: testCase, format: "decode/base64"))

        let fromURI = Array(LZString.decompressFromEncodedURIComponent(input: testCase.uri).utf16)
        #expect(fromURI == expected, Self.diagnose(fromURI, expected, case: testCase, format: "decode/uri"))

        let utf16Payload = String(decoding: Self.units(fromHex: testCase.utf16Hex), as: UTF16.self)
        let fromUTF16 = Array(LZString.decompressFromUTF16(input: utf16Payload).utf16)
        #expect(fromUTF16 == expected, Self.diagnose(fromUTF16, expected, case: testCase, format: "decode/utf16"))

        let fromUInt8 = Array(LZString.decompressFromUInt8Array(input: Self.bytes(fromHex: testCase.uint8Hex)).utf16)
        #expect(fromUInt8 == expected, Self.diagnose(fromUInt8, expected, case: testCase, format: "decode/uint8Array"))
    }
}
