import Testing
import Foundation
@testable import LZString

/// Issue #57 の回帰テスト。
///
/// 圧縮ストリームの先頭 2 ビットのタグは 0 = 8 ビットリテラル、1 = 16 ビットリテラル、
/// 2 = 終端のみが有効。タグ 3 には分岐が無く、`c` が初期値 0 のまま後続に落ちて
/// **NUL（U+0000）を含む文字列**を返していた。壊れた入力を正常なテキストとして
/// 受理してしまい、本家 JavaScript 実装（空文字列を返す）とも一致していなかった。
///
/// Regression tests for issue #57. The initial two-bit tag only has three valid values;
/// tag 3 had no branch and fell through with the initial `c == 0`, fabricating a NUL
/// character instead of rejecting the stream as the JavaScript original does.
///
/// **NUL という復号結果そのものは不正ではない。** 正当な NUL 入力は引き続き
/// 往復できなければならないため、拒否するのはタグであって結果ではない。
/// Rejecting decoded NUL characters would be wrong: genuine NUL input must still work.
@Suite("不正な先頭タグの拒否 / Invalid initial tag")
struct InvalidTagTests {
    /// Issue に記載された、先頭タグ 3 を持つ各形式の入力。
    /// 期待値は本家 lz-string 1.5.0（いずれも空文字列）。
    @Test("先頭タグ 3 を全形式で拒否する")
    func invalidInitialTagIsRejected() {
        #expect(LZString.decompressFromBase64(input: "0A==") == "")
        #expect(LZString.decompressFromEncodedURIComponent(input: "0A") == "")
        #expect(LZString.decompressFromUTF16(input: "\u{6820} ") == "")
        #expect(LZString.decompressFromUInt8Array(input: [0xD0, 0x00]) == "")

        // Data は同じストリームのリトルエンディアン表現。
        #expect(LZString.decompress(input: Data([0x00, 0xD0])) == "")
    }

    /// 戻り値が空であることをコードユニット単位でも固定する。
    /// `== ""` だけだと将来 NUL 1 文字を返す実装に戻っても気づける保証が弱い。
    @Test("拒否された入力のコードユニット列が空である")
    func rejectedInputProducesNoCodeUnits() {
        #expect(Array(LZString.decompressFromBase64(input: "0A==").utf16) == [])
        #expect(Array(LZString.decompressFromEncodedURIComponent(input: "0A").utf16) == [])
        #expect(Array(LZString.decompressFromUTF16(input: "\u{6820} ").utf16) == [])
        #expect(Array(LZString.decompressFromUInt8Array(input: [0xD0, 0x00]).utf16) == [])
        #expect(Array(LZString.decompress(input: Data([0x00, 0xD0])).utf16) == [])
    }

    /// 正当な NUL を含む入力は、可逆な全形式で往復できなければならない。
    /// 「NUL が出たら失敗」という実装にすると、ここで落ちる。
    @Test("NUL を含む正当な入力は往復する", arguments: ["\u{0}", "a\u{0}b", "\u{0}\u{0}", "\u{0}abc", "abc\u{0}"])
    func genuineNulInputRoundTrips(input: String) {
        let expected = Array(input.utf16)

        #expect(Array(LZString.decompressFromBase64(input: LZString.compressToBase64(input: input)).utf16) == expected)
        #expect(Array(LZString.decompressFromEncodedURIComponent(input: LZString.compressToEncodedURIComponent(input: input)).utf16) == expected)
        #expect(Array(LZString.decompressFromUTF16(input: LZString.compressToUTF16(input: input)).utf16) == expected)
        #expect(Array(LZString.decompressFromUInt8Array(input: LZString.compressToUInt8Array(input: input)).utf16) == expected)

        let data: Data = LZString.compress(input: input)
        #expect(Array(LZString.decompress(input: data).utf16) == expected)
    }

    /// 有効なタグ 0 / 1 / 2 の経路が壊れていないことを確認する。
    @Test("有効な先頭タグの経路が保たれている")
    func validInitialTagsStillWork() {
        // タグ 0: 8 ビットリテラル（U+0000〜U+00FF）
        #expect(LZString.decompressFromBase64(input: LZString.compressToBase64(input: "a")) == "a")
        #expect(LZString.decompressFromBase64(input: LZString.compressToBase64(input: "\u{FF}")) == "\u{FF}")

        // タグ 1: 16 ビットリテラル（U+0100 以上）
        #expect(LZString.decompressFromBase64(input: LZString.compressToBase64(input: "\u{100}")) == "\u{100}")
        #expect(LZString.decompressFromBase64(input: LZString.compressToBase64(input: "あ")) == "あ")

        // タグ 2: 空入力の終端コード（issue #33）
        #expect(LZString.compressToBase64(input: "") == "Q===")
        #expect(LZString.decompressFromBase64(input: "Q===") == "")
    }
}
