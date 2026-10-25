import Testing
import Foundation
@testable import LZString

/// Issue #21 の回帰テスト。
/// 以前は不完全・不正な入力でビット読み出しが入力長を超え、
/// `String index is out of bounds` などでプロセスごと落ちていた。
///
/// Regression tests for issue #21. Truncated or malformed input used to read past
/// the end of the buffer and terminate the process.
///
/// 失敗時の戻り値は空文字列。本家 JavaScript 実装 (pieroxy/lz-string 1.5.0) も
/// 同じ入力に対して "" を返すことを確認済み。
/// The documented failure result is an empty string, matching the original
/// JavaScript implementation for the same inputs.
@Suite("不完全な入力のハンドリング / Truncated input")
struct TruncatedInputTests {
    static let text = "Lorem ipsum dolor sit amet, consectetur adipiscing elit"
    static let validBase64 = "DIewTgpgtgBAlgBwM4FdYBMQBtwyXAFxgEMoICAaGAYxADskJqDyUwT1E4lq46BzGBCyEgA="

    @Test("Issue #21 の最小再現: 1文字の Base64 入力で落ちない")
    func minimalReproduction() {
        #expect(LZString.decompressFromBase64(input: "A") == "")
    }

    @Test("不完全・不正な入力は全形式で空文字列を返す")
    @available(*, deprecated, message: "生 String 形式 (#22) の検証を含む")
    func malformedInputReturnsEmptyString() {
        #expect(LZString.decompressFromBase64(input: "A") == "")
        #expect(LZString.decompressFromBase64(input: "!!!!") == "")
        #expect(LZString.decompressFromEncodedURIComponent(input: "A") == "")
        #expect(LZString.decompressFromUTF16(input: "A") == "")
        #expect(LZString.decompress(input: "A") == "")
    }

    /// 1 バイトだけの入力は `!input.isEmpty` の公開ガードを通過してしまい、
    /// ペアの 2 バイト目を読んだ時点で落ちていた。
    @Test("バイト列が2バイトに満たない場合も落ちない")
    func binaryInputShorterThanOneCodeUnit() {
        #expect(LZString.decompressFromUInt8Array(input: [0x01]) == "")
        #expect(LZString.decompress(input: Data([0x01])) == "")
    }

    /// 正常な圧縮データのあらゆる切り詰めを試す。
    /// 1 つでもトラップすればテストプロセスごと落ちるため、これ自体が回帰検出になる。
    @Test("あらゆる長さに切り詰めた入力で落ちない")
    func everyTruncationIsSafe() {
        for length in 1...Self.validBase64.count {
            let truncated = String(Self.validBase64.prefix(length))
            let decoded = LZString.decompressFromBase64(input: truncated)

            // 末尾のパディング分を除けば本家と同じく全文が復元できる。
            if length >= 70 {
                #expect(decoded == Self.text)
            }
        }
    }

    /// 入力の末尾ちょうどでビットを使い切る正常な入力が、
    /// 境界チェックの追加で壊れていないことを確認する。
    @Test("境界ちょうどで終わる正常な入力は復号できる")
    func validInputAtExactBufferBoundaryStillDecodes() {
        #expect(LZString.decompressFromBase64(input: Self.validBase64) == Self.text)

        for input in ["a", "aa", "ab", "hello world", "ああ", "🥺"] {
            #expect(LZString.decompressFromBase64(input: LZString.compressToBase64(input: input)) == input)
            #expect(LZString.decompressFromEncodedURIComponent(input: LZString.compressToEncodedURIComponent(input: input)) == input)
            #expect(LZString.decompressFromUTF16(input: LZString.compressToUTF16(input: input)) == input)
            #expect(LZString.decompressFromUInt8Array(input: LZString.compressToUInt8Array(input: input)) == input)

            let compressed: Data = LZString.compress(input: input)
            #expect(LZString.decompress(input: compressed) == input)
        }
    }
}
