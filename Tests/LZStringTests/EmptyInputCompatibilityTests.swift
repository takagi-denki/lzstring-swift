import Testing
import Foundation
@testable import LZString

/// Issue #33 の回帰テスト。
///
/// 本家 JavaScript 実装は空文字列と null を区別し、空文字列に対しても終端コードを
/// 出力する。Swift 版は空文字列で早期 return していたため出力が一致していなかった。
///
/// Regression tests for issue #33. The original JavaScript implementation distinguishes
/// an empty string from null and still emits the end-of-stream code for an empty string;
/// the Swift compressors used to return early instead.
///
/// 期待値は pieroxy/lz-string 1.5.0 を Node で実行して得た固定値。
/// 往復テストだけではこの不一致を検出できない（どちらの表現も「空」に見えるため）、
/// 各形式の出力を JS の固定値と直接突き合わせる。
///
/// Expected values are fixed outputs from lz-string 1.5.0 under Node. A round-trip test
/// cannot detect this mismatch, so each format's output is compared against JS directly.
@Suite("空入力の JS 互換性 / Empty input compatibility")
struct EmptyInputCompatibilityTests {
    @Test("Base64 の空入力出力が JS と一致する")
    func base64MatchesJavaScript() {
        #expect(LZString.compressToBase64(input: "") == "Q===")
    }

    @Test("URI 形式の空入力出力が JS と一致する")
    func uriMatchesJavaScript() {
        #expect(LZString.compressToEncodedURIComponent(input: "") == "Q")
    }

    @Test("UTF16 形式の空入力出力が JS と一致する")
    func utf16MatchesJavaScript() {
        #expect(Array(LZString.compressToUTF16(input: "").utf16) == [8224, 32])
    }

    @Test("UInt8Array の空入力出力が JS と一致する")
    func uint8ArrayMatchesJavaScript() {
        #expect(LZString.compressToUInt8Array(input: "") == [64, 0])
    }

    /// Data はリトルエンディアンのバイト順を保つため、JS の [64, 0] に対して [0, 64]。
    @Test("Data の空入力出力がリトルエンディアンで一致する")
    func dataMatchesJavaScript() {
        let compressed: Data = LZString.compress(input: "")
        #expect([UInt8](compressed) == [0, 64])
    }

    /// 生 String 形式は非推奨 (#22) だが、出力自体は JS と一致する。
    @Test("生 String 形式の空入力出力が JS と一致する")
    @available(*, deprecated, message: "非推奨の生 String 形式 (#22) を意図的に検証する")
    func rawStringMatchesJavaScript() {
        let compressed: String = LZString.compress(input: "")
        #expect(Array(compressed.utf16) == [16384])
    }

    /// 空入力を圧縮した結果は、展開すると空文字列に戻る。
    @Test("空入力の圧縮結果が往復する")
    func emptyInputRoundTrips() {
        #expect(LZString.decompressFromBase64(input: LZString.compressToBase64(input: "")) == "")
        #expect(LZString.decompressFromEncodedURIComponent(input: LZString.compressToEncodedURIComponent(input: "")) == "")
        #expect(LZString.decompressFromUTF16(input: LZString.compressToUTF16(input: "")) == "")
        #expect(LZString.decompressFromUInt8Array(input: LZString.compressToUInt8Array(input: "")) == "")

        let compressed: Data = LZString.compress(input: "")
        #expect(LZString.decompress(input: compressed) == "")
    }

    /// JS 版が生成した空入力の圧縮データを、こちら側で展開できる。
    @Test("JS が生成した空入力データを展開できる")
    func decompressesJavaScriptProducedEmptyPayloads() {
        #expect(LZString.decompressFromBase64(input: "Q===") == "")
        #expect(LZString.decompressFromEncodedURIComponent(input: "Q") == "")
        #expect(LZString.decompressFromUInt8Array(input: [64, 0]) == "")
        #expect(LZString.decompress(input: Data([0, 64])) == "")
    }

    /// 展開 API の空入力時の挙動は従来どおり（空文字列を返す）。
    /// JS は null を返すが、Swift の戻り値型は String のため空文字列で表す。
    @Test("展開 API の空入力の挙動は変わらない")
    func decompressorEmptyInputBehaviourIsUnchanged() {
        #expect(LZString.decompressFromBase64(input: "") == "")
        #expect(LZString.decompressFromEncodedURIComponent(input: "") == "")
        #expect(LZString.decompressFromUTF16(input: "") == "")
        #expect(LZString.decompressFromUInt8Array(input: []) == "")
        #expect(LZString.decompress(input: Data()) == "")
    }
}
