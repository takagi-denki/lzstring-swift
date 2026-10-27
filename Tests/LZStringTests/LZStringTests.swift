import Testing
import Foundation
@testable import LZString

@Suite("LZString Tests")
struct LZStringTests {
    static let text = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum."
    
    // Helper for loading test fixtures.
    func getTestDataURL(name: String) -> URL {
        // Use a path relative to the package root so it works both in CI and locally.
        return URL(fileURLWithPath: "Tests/Resources/\(name).txt")
    }

    @Test("Standard compression and decompression")
    func compressAndDecompress() throws {
        let compressUrl = getTestDataURL(name: "compress")
        let expectedData = try Data(contentsOf: compressUrl)
        
        let compressed : Data = LZString.compress(input: Self.text)
        #expect(compressed == expectedData)
        
        let decompressed = LZString.decompress(input: compressed)
        #expect(decompressed == Self.text)
    }

    @Test("Emoji compression and decompression", arguments: [
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

    @Test("UTF16 format compression and decompression")
    func utf16Tests() throws {
        let url = getTestDataURL(name: "compress_utf16")
        let expectedUtf16 = try String(contentsOf: url, encoding: .utf16LittleEndian)
        
        let compressed = LZString.compressToUTF16(input: Self.text)
        // String == compares by canonical equivalence, so compare code units (issue #40).
        #expect(Array(compressed.utf16) == Array(expectedUtf16.utf16))
        
        let decompressed = LZString.decompressFromUTF16(input: compressed)
        #expect(Array(decompressed.utf16) == Array(Self.text.utf16))
    }

    @Test("Base64 format compression and decompression")
    func base64Tests() throws {
        let url = getTestDataURL(name: "compress_base64")
        let expectedBase64 = try String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        
        let compressed = LZString.compressToBase64(input: Self.text)
        #expect(compressed == expectedBase64)
        
        let decompressed = LZString.decompressFromBase64(input: compressed)
        #expect(decompressed == Self.text)
    }

    @Test("URI format compression and decompression")
    func uriTests() throws {
        let url = getTestDataURL(name: "compress_uri")
        let expectedUri = try String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        
        let compressed = LZString.compressToEncodedURIComponent(input: Self.text)
        #expect(compressed == expectedUri)
        
        let decompressed = LZString.decompressFromEncodedURIComponent(input: compressed)
        #expect(decompressed == Self.text)
    }

    @Test("UInt8Array format compression and decompression")
    func uint8ArrayTests() throws {
        let url = getTestDataURL(name: "compress_uint8")
        let data = try Data(contentsOf: url)
        let expectedArray = [UInt8](data)
        
        let compressed = LZString.compressToUInt8Array(input: Self.text)
        #expect(compressed == expectedArray)
        
        let decompressed = LZString.decompressFromUInt8Array(input: compressed)
        #expect(decompressed == Self.text)
    }

    /// Compressing an empty string emits the end-of-stream code, matching the original
    /// JavaScript implementation (issue #33). Decompressors return "" for empty input.
    @Test("Empty string handling")
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
