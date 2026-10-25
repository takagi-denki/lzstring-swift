import Testing
import Foundation
@testable import LZString

@Suite("LZString Tests")
struct LZStringTests {
    static let text = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum."
    
    // テストデータの読み込み用ヘルパー
    func getTestDataURL(name: String) -> URL {
        // CI環境(ubuntu-latest)やローカルでの実行を考慮し、プロジェクトルートからの相対パスを使用
        return URL(fileURLWithPath: "Tests/Resources/\(name).txt")
    }

    @Test("標準的な圧縮と展開の検証")
    func compressAndDecompress() throws {
        let compressUrl = getTestDataURL(name: "compress")
        let expectedData = try Data(contentsOf: compressUrl)
        
        let compressed : Data = LZString.compress(input: Self.text)
        #expect(compressed == expectedData)
        
        let decompressed = LZString.decompress(input: compressed)
        #expect(decompressed == Self.text)
    }

    @Test("絵文字の圧縮と展開", arguments: [
        ("🥺", "nwbi9do=")
    ])
    func emojiTests(input: String, expectedBase64: String) {
        // Base64
        let compressedBase64 = LZString.compressToBase64(input: input)
        #expect(compressedBase64 == expectedBase64)
        
        let decompressedBase64 = LZString.decompressFromBase64(input: expectedBase64)
        #expect(decompressedBase64 == input)
        
        // Data
        let expectedData = Data([0x06, 0x9f, 0xf5, 0xe2, 0x00, 0xda])
        let compressedData: Data = LZString.compress(input: input)
        #expect(compressedData == expectedData)
        
        let decompressedData = LZString.decompress(input: expectedData)
        #expect(decompressedData == input)
    }

    @Test("UTF16形式の圧縮と展開")
    func utf16Tests() throws {
        let url = getTestDataURL(name: "compress_utf16")
        let expectedUtf16 = try String(contentsOf: url, encoding: .utf16LittleEndian)
        
        let compressed = LZString.compressToUTF16(input: Self.text)
        // String の == は正規等価で比較するため、UTF-16 コードユニット列で突き合わせる (issue #40)。
        #expect(Array(compressed.utf16) == Array(expectedUtf16.utf16))
        
        let decompressed = LZString.decompressFromUTF16(input: compressed)
        #expect(Array(decompressed.utf16) == Array(Self.text.utf16))
    }

    @Test("Base64形式の圧縮と展開")
    func base64Tests() throws {
        let url = getTestDataURL(name: "compress_base64")
        let expectedBase64 = try String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        
        let compressed = LZString.compressToBase64(input: Self.text)
        #expect(compressed == expectedBase64)
        
        let decompressed = LZString.decompressFromBase64(input: compressed)
        #expect(decompressed == Self.text)
    }

    @Test("URI形式の圧縮と展開")
    func uriTests() throws {
        let url = getTestDataURL(name: "compress_uri")
        let expectedUri = try String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        
        let compressed = LZString.compressToEncodedURIComponent(input: Self.text)
        #expect(compressed == expectedUri)
        
        let decompressed = LZString.decompressFromEncodedURIComponent(input: compressed)
        #expect(decompressed == Self.text)
    }

    @Test("UInt8Array形式の圧縮と展開")
    func uint8ArrayTests() throws {
        let url = getTestDataURL(name: "compress_uint8")
        let data = try Data(contentsOf: url)
        let expectedArray = [UInt8](data)
        
        let compressed = LZString.compressToUInt8Array(input: Self.text)
        #expect(compressed == expectedArray)
        
        let decompressed = LZString.decompressFromUInt8Array(input: compressed)
        #expect(decompressed == Self.text)
    }

    /// 空文字列の圧縮は終端コードを出力する（本家 JS 版と同じ挙動、issue #33）。
    /// 展開側は空入力に対して空文字列を返す。
    @Test("空文字列のハンドリング")
    func emptyInputTests() {
        #expect([UInt8](LZString.compress(input: "") as Data) == [0, 64])
        #expect(LZString.compressToUTF16(input: "") == "\u{2020} ")
        #expect(LZString.compressToBase64(input: "") == "Q===")
        #expect(LZString.compressToEncodedURIComponent(input: "") == "Q")
        #expect(LZString.compressToUInt8Array(input: "") == [64, 0])

        #expect(LZString.decompress(input: Data()) == "")
        #expect(LZString.decompressFromBase64(input: "") == "")
        #expect(LZString.decompressFromEncodedURIComponent(input: "") == "")
        #expect(LZString.decompressFromUTF16(input: "") == "")
        #expect(LZString.decompressFromUInt8Array(input: []) == "")
    }
}
