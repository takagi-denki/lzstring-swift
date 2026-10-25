import Testing
import Foundation
@testable import LZString

/// Issue #20 の回帰テスト。繰り返し文字は LZW の KwKwK ケースを踏み、
/// 以前は展開時に `Index out of range` でクラッシュしていた。
///
/// Regression tests for issue #20. Repeated characters hit the LZW KwKwK case,
/// which used to trap with `Index out of range` during decompression.
///
/// 期待値は本家 JavaScript 実装 (pieroxy/lz-string 1.5.0) の出力。
/// Expected values are produced by the original JavaScript implementation.
@Suite("繰り返し文字の圧縮と展開 / Repeated characters")
struct RepeatedCharacterTests {
    static let cases: [(input: String, base64: String, uri: String)] = [
        ("aa", "IbI=", "IbI"),
        ("aaa", "IYo=", "IYo"),
        ("aaaa", "IY5A", "IY5A"),
        ("ababab", "IYI1qA==", "IYI1qA"),
        ("abcabcabc", "IYIwxqHkA===", "IYIwxqHkA"),
        ("aaa bbb aaa bbb", "IYgECNNFgyg=", "IYgECNNFgyg"),
        ("ああああ", "kIMOQ===", "kIMOQ"),
        ("🥺🥺🥺", "nwbi9d2o", "nwbi9d2o"),
    ]

    @Test("Issue #20 の最小再現: \"aaa\" が往復する")
    func minimalReproduction() {
        let encoded = LZString.compressToBase64(input: "aaa")
        #expect(encoded == "IYo=")
        #expect(LZString.decompressFromBase64(input: encoded) == "aaa")
    }

    @Test("圧縮結果が JS 版と一致する", arguments: cases)
    func matchesJavaScriptOutput(input: String, expectedBase64: String, expectedUri: String) {
        #expect(LZString.compressToBase64(input: input) == expectedBase64)
        #expect(LZString.compressToEncodedURIComponent(input: input) == expectedUri)
    }

    /// 可逆な全形式で往復を検証する。
    /// 生の String 形式はサロゲートを U+FFFD に置換する既知の不具合 (issue #22) があるため対象外。
    @Test("全形式で往復する", arguments: cases)
    func roundTripsThroughEveryFormat(input: String, expectedBase64: String, expectedUri: String) {
        #expect(LZString.decompressFromBase64(input: expectedBase64) == input)
        #expect(LZString.decompressFromEncodedURIComponent(input: expectedUri) == input)
        #expect(LZString.decompressFromUTF16(input: LZString.compressToUTF16(input: input)) == input)
        #expect(LZString.decompressFromUInt8Array(input: LZString.compressToUInt8Array(input: input)) == input)

        let compressed: Data = LZString.compress(input: input)
        #expect(LZString.decompress(input: compressed) == input)
    }

    @Test("長い繰り返し文字列が往復する")
    func longRunOfRepeatedCharacters() {
        let input = String(repeating: "x", count: 500)
        #expect(LZString.compressToBase64(input: input) == "B418ZXTt/DFOS1b0c17Pd/wYWEA=")
        #expect(LZString.decompressFromBase64(input: LZString.compressToBase64(input: input)) == input)
    }
}
