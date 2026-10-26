import Testing
import Foundation
@testable import LZString

/// Issue #42 — 全展開形式の切り詰め・不正入力テスト。
///
/// #21 / #32 の回帰テストを置き換えるものではなく、網羅範囲を広げるもの。
/// 既存スイートは Base64 の 1 ペイロードだけを全長で切り詰めていた。
///
/// 読み出し境界は形式ごとに異なる。Base64 / URI は文字、UTF16 は
/// **コードユニット**（`String.prefix` は Character 単位で数えるため使わない）、
/// Data / UInt8Array はバイト。
///
/// 期待値は pieroxy/lz-string 1.5.0 を Node で実行した固定値。
@Suite("不正・切り詰め入力の網羅 / Malformed and truncated input coverage")
struct MalformedInputTests {
    struct Vector: Sendable, CustomStringConvertible {
        let input: String
        let base64: String
        let uri: String
        let utf16Units: [UInt16]
        let uint8: [UInt8]
        /// JS が非空を返す切り詰め長 -> その結果。記載のない長さは空文字列。
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

    /// 形式ごとの読み出し境界で切り詰める。
    static func truncate(_ vector: Vector, _ format: String, _ n: Int) -> String {
        switch format {
        case "base64":
            return LZString.decompressFromBase64(input: String(vector.base64.prefix(n)))
        case "uri":
            return LZString.decompressFromEncodedURIComponent(input: String(vector.uri.prefix(n)))
        case "utf16":
            // String.prefix は Character 単位で数えるため、コードユニット単位で切る。
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

    /// 本ライブラリと本家 JS で結果が異なる既知の位置（方針として受け入れている差異）。
    ///
    /// JS は入力末尾を超えた読み出しを NaN 経由で 0 ビットとして扱うため、
    /// 終端コードの末尾ビットが欠けていても復号が成立する。本ライブラリは #21 以降、
    /// 入力が尽きた時点で失敗する（空文字列）。完全な圧縮出力では差は出ず、
    /// 意図的に切り詰めた入力でのみ観測される。
    ///
    /// Known positions where this library is stricter than the JS original: JS treats reads
    /// past the end as zero bits and can still finish, while this library fails once the
    /// input is exhausted (#21). Only observable on deliberately truncated input.
    static let stricterThanJavaScript: Set<String> = [
        "a/base64@2",
        "a/uri@2",
        "aaa/utf16@1",
    ]

    // MARK: - 網羅的な切り詰め

    /// 切り詰めた入力は「完全に復元できる」か「空文字列」のどちらかで、
    /// **途中まで復号された壊れたテキストを返さない**。
    /// 1 つでもトラップすればテストプロセスごと落ちるため、安全性の検証も兼ねる。
    @Test("全形式・全長の切り詰めが安全で、部分的な文字列を返さない", arguments: vectors)
    func everyTruncationIsSafeAndNeverPartial(vector: Vector) {
        for format in Self.formats {
            for n in 0...Self.total(vector, format) {
                let decoded = Self.truncate(vector, format, n)

                #expect(decoded.isEmpty || decoded == vector.input,
                        "\(vector.input)/\(format)@\(n): 部分的な結果 \(decoded.debugDescription)")
            }
        }
    }

    /// 全形式・全長について本家 JS の結果と突き合わせる。
    /// 一致しない位置は stricterThanJavaScript に明示したものだけであることを保証する。
    @Test("切り詰め結果が JS と一致する（既知の差異を除く）", arguments: vectors)
    func truncationMatchesJavaScript(vector: Vector) {
        for format in Self.formats {
            let jsDecodes = Set(vector.jsNonEmpty[format] ?? [])

            for n in 0...Self.total(vector, format) {
                let key = "\(vector.input)/\(format)@\(n)"
                let decoded = Self.truncate(vector, format, n)

                if Self.stricterThanJavaScript.contains(key) {
                    #expect(decoded.isEmpty, "\(key): 既知の差異（JS は復号成立、本実装は失敗）の想定が崩れている")
                    continue
                }

                // JS が例外を投げる位置（UInt8Array の奇数バイト長）では JS 側に期待値がない。
                // 本実装はトラップせず値を返す契約なので、ここでは一致を要求しない。
                let jsThrows = (format == "uint8" && n % 2 == 1 && n > 0)
                if jsThrows { continue }

                let expected = jsDecodes.contains(n) ? vector.input : ""
                #expect(decoded == expected, "\(key): swift=\(decoded.debugDescription) js=\(expected.debugDescription)")
            }
        }
    }

    /// 復号が成立する最小長と、その 1 つ手前を名前付きで固定する。
    /// 「70 文字以上なら全文」のようなマジックナンバーの代わりに、
    /// 形式ごとの実際の境界を記録する。
    @Test("復号が成立する最小長の境界を固定する", arguments: vectors)
    func decodingThresholdIsPinned(vector: Vector) {
        for format in Self.formats {
            guard let smallest = (vector.jsNonEmpty[format] ?? []).min() else { continue }

            let key = "\(vector.input)/\(format)@\(smallest)"
            if Self.stricterThanJavaScript.contains(key) { continue }

            #expect(Self.truncate(vector, format, smallest) == vector.input,
                    "\(key): 最小長で復号できるはず")

            if smallest > 0 {
                #expect(Self.truncate(vector, format, smallest - 1).isEmpty,
                        "\(vector.input)/\(format)@\(smallest - 1): 境界の 1 つ手前は失敗するはず")
            }
        }
    }

    // MARK: - Data スライス

    /// 空・1 バイト・奇数バイト・startIndex が 0 でないスライス。#32 の回帰を保ちつつ範囲を広げる。
    @Test("Data の退化したスライスがトラップしない", arguments: vectors)
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

            // スライスをさらに全長で切り詰めてもトラップしない。
            for length in 0...encoded.count {
                let truncated = slice.prefix(length)
                let decoded = LZString.decompress(input: truncated)
                #expect(decoded.isEmpty || decoded == vector.input,
                        "offset=\(offset) length=\(length): 部分的な結果 \(decoded.debugDescription)")
            }
        }

        // 奇数バイト長
        for odd in stride(from: 1, to: encoded.count, by: 2) {
            let decoded = LZString.decompress(input: encoded.prefix(odd))
            #expect(decoded.isEmpty || decoded == vector.input)
        }
    }

    // MARK: - 決定的な変異

    /// 先頭タグ・辞書コード・終端ビットの改変、英数字以外の文字、低い UTF16 値など。
    /// **すべての変異が無効とは限らない**（別の有効なテキストを表す場合がある）ため、
    /// トラップしないことと、結果が有限であることだけを要求する。
    @Test("決定的な変異入力がトラップもハングもしない", arguments: vectors)
    func boundedDeterministicMutations(vector: Vector) {
        // Base64 / URI アルファベット外の文字を各位置に注入
        for (index, intruder) in ["あ", "\u{0}", "~", "\u{FFFF}", " ", "%"].enumerated() {
            let position = vector.base64.isEmpty ? 0 : index % vector.base64.count
            var mutated = Array(vector.base64)
            if !mutated.isEmpty { mutated[position] = Character(intruder) }
            _ = LZString.decompressFromBase64(input: String(mutated))

            var mutatedURI = Array(vector.uri)
            if !mutatedURI.isEmpty { mutatedURI[position % max(mutatedURI.count, 1)] = Character(intruder) }
            _ = LZString.decompressFromEncodedURIComponent(input: String(mutatedURI))
        }

        // UTF16 形式に低いコードユニットを注入（nextValue が負になりうる経路）
        for unit in [UInt16(0), 1, 31] {
            var units = vector.utf16Units
            if !units.isEmpty {
                units[0] = unit
                _ = LZString.decompressFromUTF16(input: String(decoding: units, as: UTF16.self))
            }
        }

        // 各バイトの最下位ビットを反転（終端ビットの改変を含む）
        for index in vector.uint8.indices {
            var bytes = vector.uint8
            bytes[index] ^= 0x01
            let decoded = LZString.decompressFromUInt8Array(input: bytes)
            // 別の有効なテキストになりうるので内容は問わない。
            _ = decoded
        }

        // 先頭タグの改変
        if !vector.uint8.isEmpty {
            for pattern in [UInt8(0x00), 0xFF, 0x80] {
                var bytes = vector.uint8
                bytes[0] = pattern
                _ = LZString.decompressFromUInt8Array(input: bytes)
            }
        }
    }

    // MARK: - 有効な入力の保護

    /// 境界ちょうどで終わる正常な入力と、URI の '+' が空白に変換された入力が
    /// 引き続き受理されることを保証する（防御を固めた結果これらを弾かないこと）。
    @Test("有効な入力の正規化が壊れていない", arguments: vectors)
    func validInputNormalisationIsPreserved(vector: Vector) {
        #expect(LZString.decompressFromBase64(input: vector.base64) == vector.input)
        #expect(LZString.decompressFromEncodedURIComponent(input: vector.uri) == vector.input)
        #expect(LZString.decompressFromUTF16(input: vector.utf16) == vector.input)
        #expect(LZString.decompressFromUInt8Array(input: vector.uint8) == vector.input)
        #expect(LZString.decompress(input: LZString.compress(input: vector.input) as Data) == vector.input)

        // URL デコーダが '+' を空白に変える経路。
        let spaced = vector.uri.replacingOccurrences(of: "+", with: " ")
        #expect(LZString.decompressFromEncodedURIComponent(input: spaced) == vector.input,
                "\(vector.input): '+' を空白にした URI が復元できない")
    }

    /// '+' を実際に含むペイロードで、空白置換の経路が本当に働いていることを確かめる。
    /// （'+' を含まない入力では置換が何もしないため、保護になっていない）
    @Test("'+' を含む URI ペイロードが空白経由で復元できる")
    func uriPayloadContainingPlusRoundTripsThroughSpace() throws {
        let vector = try #require(Self.vectors.first { $0.uri.contains("+") })

        #expect(vector.uri.contains("+"), "このベクタは '+' を含んでいる必要がある")

        let spaced = vector.uri.replacingOccurrences(of: "+", with: " ")
        #expect(spaced != vector.uri)
        #expect(LZString.decompressFromEncodedURIComponent(input: spaced) == vector.input)
    }
}
