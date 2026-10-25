import Testing
import Foundation
@testable import LZString

/// Issue #22 — 生の `String` 形式の制約を固定するテスト。
///
/// `compress(input:) -> String` は生の 16 ビットストリームをそのまま `String` として返すが、
/// ストリームには対になっていない UTF-16 サロゲートが現れることがある。Swift の `String` は
/// それを表現できないため `U+FFFD` に置換され、データが失われる。
/// この形式は非推奨とし、可逆な形式へ誘導する。
///
/// Pins the limitation of the raw `String` format. Swift's `String` cannot hold unpaired
/// UTF-16 surrogates, so they are replaced with `U+FFFD` and the data is destroyed.
/// The format is deprecated in favour of the lossless ones.
@Suite("生 String 形式の制約 / Raw String format")
struct RawStringFormatTests {
    /// Issue #22 に記載された再現入力。4 番目のコードユニットがサロゲートになる。
    static let input = "test1111"

    @Test("生 String 形式はサロゲートを失い往復できない")
    @available(*, deprecated, message: "非推奨の生 String 形式 (#22) を意図的に検証する")
    func rawStringFormatIsLossy() {
        let compressed: String = LZString.compress(input: Self.input)

        // 本来 4 番目は 55616 (0xD940) だが、孤立サロゲートのため U+FFFD に置換される。
        #expect(Array(compressed.utf16) == [2949, 12494, 49292, 0xFFFD])
        #expect(LZString.decompress(input: compressed) != Self.input)
    }

    /// 同じ入力が、誘導先の可逆な形式では正しく往復することを保証する。
    @Test("同じ入力が可逆な形式では往復する")
    func losslessFormatsRoundTripTheSameInput() {
        let data: Data = LZString.compress(input: Self.input)
        let units = stride(from: 0, to: data.count, by: 2).map { Int(data[$0]) | (Int(data[$0 + 1]) << 8) }

        // Data 形式はサロゲート値をそのまま保持する。
        #expect(units == [2949, 12494, 49292, 55616])
        #expect(LZString.decompress(input: data) == Self.input)

        #expect(LZString.decompressFromUInt8Array(input: LZString.compressToUInt8Array(input: Self.input)) == Self.input)
        #expect(LZString.decompressFromUTF16(input: LZString.compressToUTF16(input: Self.input)) == Self.input)
        #expect(LZString.decompressFromBase64(input: LZString.compressToBase64(input: Self.input)) == Self.input)
        #expect(LZString.decompressFromEncodedURIComponent(input: LZString.compressToEncodedURIComponent(input: Self.input)) == Self.input)
    }
}
