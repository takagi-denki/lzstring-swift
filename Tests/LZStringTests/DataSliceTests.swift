import Testing
import Foundation
@testable import LZString

/// Issue #32 の回帰テスト。
/// `Data` はスライスすると `startIndex` が 0 から始まらない。0 始まりを前提に
/// 添字アクセスしていたため、完全な圧縮データでも範囲外アクセスで落ちていた。
/// 不完全な入力が原因の #21 とは別の問題。
///
/// Regression tests for issue #32. A sliced `Data` does not start at index 0, and the
/// decoder assumed zero-based indices, so even a complete payload trapped. This is
/// distinct from issue #21, which was about truncated input.
@Suite("Data スライスの展開 / Decompressing Data slices")
struct DataSliceTests {
    static let text = "hello"

    /// Issue に記載された最小再現。2 バイトのヘッダーを剥がしたペイロード。
    @Test("Issue #32 の最小再現: ヘッダーを除いたスライスが展開できる")
    func minimalReproduction() {
        let encoded: Data = LZString.compress(input: Self.text)

        var packet = Data([0, 0])
        packet.append(encoded)

        let payload = packet.dropFirst(2)
        #expect(payload.startIndex == 2)
        #expect(LZString.decompress(input: payload) == Self.text)
    }

    /// スライスと、同じバイト列を 0 始まりに作り直した Data が同じ結果になること。
    @Test("スライスと再構築した Data の結果が一致する", arguments: [0, 1, 2, 3, 7, 16])
    func sliceMatchesRebasedData(offset: Int) {
        let encoded: Data = LZString.compress(input: Self.text)

        var packet = Data(repeating: 0xAB, count: offset)
        packet.append(encoded)

        let slice = packet.dropFirst(offset)
        #expect(slice.startIndex == offset)
        #expect(LZString.decompress(input: slice) == Self.text)
        #expect(LZString.decompress(input: slice) == LZString.decompress(input: Data(slice)))
    }

    /// 末尾を削ったスライスでも 0 始まりを前提にしない。
    @Test("末尾側のスライスでも落ちない")
    func trailingSliceIsSafe() {
        let encoded: Data = LZString.compress(input: Self.text)

        var packet = encoded
        packet.append(contentsOf: [0xFF, 0xFF])

        let payload = packet.dropLast(2)
        #expect(LZString.decompress(input: payload) == Self.text)
    }

    /// #21 で定めた失敗時の挙動（空文字列・トラップしない）をスライスでも維持する。
    @Test("空・1バイト・切り詰めスライスでもトラップしない")
    func degenerateSlicesPreserveFailureBehaviour() {
        let encoded: Data = LZString.compress(input: Self.text)
        var packet = Data([0, 0])
        packet.append(encoded)

        #expect(LZString.decompress(input: packet.dropFirst(packet.count)) == "")
        #expect(LZString.decompress(input: packet.dropFirst(packet.count - 1)) == "")

        // あらゆる長さに切り詰めたスライス。1 つでもトラップすればテストごと落ちる。
        for length in 0...encoded.count {
            _ = LZString.decompress(input: packet.dropFirst(2).prefix(length))
        }
    }

    /// 非 ASCII やサロゲートペアを含む入力でもスライス経由で往復できる。
    @Test("スライス経由でも各種入力が往復する", arguments: ["a", "aaa", "ああ", "🥺", "\u{FEFF}abc", "Lorem ipsum dolor sit amet"])
    func sliceRoundTripsVariousInputs(input: String) {
        let encoded: Data = LZString.compress(input: input)

        var packet = Data([0xDE, 0xAD, 0xBE, 0xEF])
        packet.append(encoded)

        #expect(LZString.decompress(input: packet.dropFirst(4)) == input)
    }
}
