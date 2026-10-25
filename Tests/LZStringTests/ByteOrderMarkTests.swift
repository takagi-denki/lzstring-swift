import Testing
import Foundation
@testable import LZString

/// Issue #23 の回帰テスト。
/// 復号結果をバイト列に落として `String(data:encoding:.utf16)` に渡していたため、
/// 先頭の U+FEFF が BOM として解釈されて失われていた。
/// 先頭が U+FFFE の場合はリトルエンディアン BOM と解釈され、以降のバイト順も反転していた。
///
/// Regression tests for issue #23. The decoded units used to be serialised to bytes and
/// handed to `String(data:encoding:.utf16)`, which ate a leading U+FEFF as a BOM — and
/// read a leading U+FFFE as a little-endian BOM, flipping the byte order of the rest.
///
/// 期待値は本家 JavaScript 実装 (pieroxy/lz-string 1.5.0) の出力。
/// Expected values are produced by the original JavaScript implementation.
@Suite("BOM 文字の保持 / Byte order mark round trip")
struct ByteOrderMarkTests {
    static let cases: [(input: String, base64: String)] = [
        ("\u{FEFF}abc", "v9/EMEYMZA=="),
        ("\u{FEFF}", "v9/Q"),
        ("\u{FEFF}\u{FEFF}", "v9/yA==="),
        ("\u{FEFF}🥺", "v9/j4Nxeu0A="),
        ("ab\u{FEFF}cd", "IYI0/38MYCZA"),
        ("\u{FFFE}abc", "n//EMEYMZA=="),
        ("\u{FFFE}", "n//Q"),
        ("abc", "IYIwxkA="),
    ]

    @Test("Issue #23 の最小再現: 先頭の U+FEFF が残る")
    func minimalReproduction() {
        let input = "\u{FEFF}abc"
        let output = LZString.decompressFromBase64(input: LZString.compressToBase64(input: input))

        #expect(Array(output.utf16) == [0xFEFF, 0x61, 0x62, 0x63])
        #expect(output == input)
    }

    /// 先頭が U+FFFE の場合、以前はリトルエンディアン BOM と誤認され、
    /// 残りの文字のバイト順まで反転していた。
    @Test("先頭の U+FFFE でバイト順が反転しない")
    func leadingReversedByteOrderMark() {
        let input = "\u{FFFE}abc"
        let output = LZString.decompressFromBase64(input: LZString.compressToBase64(input: input))

        #expect(Array(output.utf16) == [0xFFFE, 0x61, 0x62, 0x63])
        #expect(output == input)
    }

    @Test("圧縮結果が JS 版と一致する", arguments: cases)
    func matchesJavaScriptOutput(input: String, expectedBase64: String) {
        #expect(LZString.compressToBase64(input: input) == expectedBase64)
    }

    /// 生の String 形式はサロゲートを U+FFFD に置換する既知の不具合 (issue #22) があるため対象外。
    @Test("可逆な全形式で往復する", arguments: cases)
    func roundTripsThroughEveryFormat(input: String, expectedBase64: String) {
        #expect(LZString.decompressFromBase64(input: expectedBase64) == input)
        #expect(LZString.decompressFromEncodedURIComponent(input: LZString.compressToEncodedURIComponent(input: input)) == input)
        #expect(LZString.decompressFromUTF16(input: LZString.compressToUTF16(input: input)) == input)
        #expect(LZString.decompressFromUInt8Array(input: LZString.compressToUInt8Array(input: input)) == input)

        let compressed: Data = LZString.compress(input: input)
        #expect(LZString.decompress(input: compressed) == input)
    }

    /// サロゲートペアと BMP 外の文字が壊れていないことを確認する。
    @Test("サロゲートペアを含む文字列が往復する", arguments: ["🥺", "🥺🥺", "a🥺b", "\u{10FFFF}", "𝄞音符"])
    func supplementaryCharactersRoundTrip(input: String) {
        #expect(LZString.decompressFromBase64(input: LZString.compressToBase64(input: input)) == input)

        let compressed: Data = LZString.compress(input: input)
        #expect(LZString.decompress(input: compressed) == input)
    }

    /// 不正な入力は引き続き空文字列を返す（issue #21 で定めた失敗値）。
    @Test("不正な入力は空文字列のまま")
    func malformedInputStillReturnsEmptyString() {
        #expect(LZString.decompressFromBase64(input: "!!!!") == "")
        #expect(LZString.decompressFromBase64(input: "A") == "")
    }
}
