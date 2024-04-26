import XCTest
@testable import LZString

class LZStringTests: XCTestCase {
    static let text = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum."
    var compressed : Data = Data()
    var compressedUtf16 : String = ""
    var compressedBase64 : String = ""
    var compressedUri : String = ""
    var compressedUInt8Array : [UInt8] = []

    func testDataURL(name : String) -> URL {
#if os(OSX) || os(iOS)
        guard let url = Bundle(for: type(of: self)).url(forResource: name, withExtension: "txt") else {
            return URL(fileURLWithPath: "./Tests/Resources/\(name).txt")
        }

        return url
#else
        return URL(fileURLWithPath: "./Tests/Resources/\(name).txt")
#endif
    }

    override func setUp() {
        do {
            let compressUrl = testDataURL(name: "compress")
            let compressUtf16Url = testDataURL(name: "compress_utf16")
            let compressBase64Url = testDataURL(name: "compress_base64")
            let compressUriUrl = testDataURL(name: "compress_uri")
            let compressUInt8Url = testDataURL(name: "compress_uint8")

            compressed = try Data(contentsOf: compressUrl)
            compressedUtf16 = try String(contentsOf: compressUtf16Url, encoding: String.Encoding.utf16LittleEndian)
            compressedBase64 = try String(contentsOf: compressBase64Url, encoding: String.Encoding.utf8)
            compressedUri = try String(contentsOf: compressUriUrl, encoding: String.Encoding.utf8)

            let compressedUInt8 = try Data(contentsOf: compressUInt8Url)
            compressedUInt8Array = [UInt8](repeating: 0, count: compressedUInt8.count)
            compressedUInt8.copyBytes(to: &compressedUInt8Array, count: compressedUInt8.count)
        } catch let e {
            XCTFail(e.localizedDescription)
        }
    }

    func testCompress() {
        let compress : Data = LZString.compress(input: LZStringTests.text)
        XCTAssertEqual(compressed, compress)
    }
    
    func testEmojiCompress() {
        let compress : Data = LZString.compress(input: "🥺")
        let expect = Data.init([0x06, 0x9f, 0xf5, 0xe2, 0x00, 0xda])
        XCTAssertEqual(expect, compress)
    }
    
    func testEmojiDecompress() {
        let decompress = LZString.decompress(input: Data.init([0x06, 0x9f, 0xf5, 0xe2, 0x00, 0xda]))
        XCTAssertEqual("🥺", decompress)
    }
    
    func testEmojiBase64Compress() {
        let compress = LZString.compressToBase64(input: "🥺")
        XCTAssertEqual("nwbi9do=", compress)
    }
    
    func testEmojiBase64Decompress() {
        let decompress = LZString.decompressFromBase64(input: "nwbi9do=")
        XCTAssertEqual("🥺", decompress)
    }

    func testDecompress() {
        let decompress = LZString.decompress(input: compressed)
        XCTAssertEqual(decompress, LZStringTests.text)
    }

    func testCompressUtf16() {
        let compress = LZString.compressToUTF16(input: LZStringTests.text)
        XCTAssertEqual(compressedUtf16, compress)
    }

    func testDecompressUtf16() {
        let decompress = LZString.decompressFromUTF16(input: compressedUtf16)
        XCTAssertEqual(decompress, LZStringTests.text)
    }

    func testCompressBase64() {
        let compress = LZString.compressToBase64(input: LZStringTests.text)
        XCTAssertEqual(compressedBase64, compress)
    }

    func testDecompressBase64() {
        let decompress = LZString.decompressFromBase64(input: compressedBase64)
        XCTAssertEqual(decompress, LZStringTests.text)
    }

    func testCompressUri() {
        let compress = LZString.compressToEncodedURIComponent(input: LZStringTests.text)
        XCTAssertEqual(compressedUri, compress)
    }

    func testDecompressUri() {
        let decompress = LZString.decompressFromEncodedURIComponent(input: compressedUri)
        XCTAssertEqual(decompress, LZStringTests.text)
    }

    func testCompressUInt8Array() {
        let compress = LZString.compressToUInt8Array(input: LZStringTests.text)
        XCTAssertEqual(compressedUInt8Array, compress)
    }

    func testDecompressUInt8Array() {
        let decompress = LZString.decompressFromUInt8Array(input: compressedUInt8Array)
        XCTAssertEqual(decompress, LZStringTests.text)
    }

    func testCompressEmpty() {
        let compress : Data = LZString.compress(input: "")
        XCTAssertEqual(compress, Data())
    }

    func testDecompressEmpty() {
        let decompress = LZString.decompress(input: Data())
        XCTAssertEqual(decompress, "")
    }

    func testCompressUTF16Empty() {
        let compress = LZString.compressToUTF16(input: "")
        XCTAssertEqual(compress, "")
    }

    func testDecompressUTF16Empty() {
        let decompress = LZString.decompressFromUTF16(input: "")
        XCTAssertEqual(decompress, "")
    }

    func testCompressBase64Empty() {
        let compress = LZString.compressToBase64(input: "")
        XCTAssertEqual(compress, "")
    }

    func testDecompressBase64Empty() {
        let decompress = LZString.decompressFromBase64(input: "")
        XCTAssertEqual(decompress, "")
    }

    func testCompressUriEmpty() {
        let compress = LZString.compressToEncodedURIComponent(input: "")
        XCTAssertEqual(compress, "")
    }

    func testDecompressUriEmpty() {
        let decompress = LZString.decompressFromEncodedURIComponent(input: "")
        XCTAssertEqual(decompress, "")
    }

    func testCompressUInt8Empty() {
        let compress = LZString.compressToUInt8Array(input: "")
        XCTAssertEqual(compress, [])
    }

    func testDecompressUInt8Empty() {
        let decompress = LZString.decompressFromUInt8Array(input: [])
        XCTAssertEqual(decompress, "")
    }

    static var allTests = [
        ("testCompress", testCompress),
        ("testEmojiCompress", testEmojiCompress),
        ("testCompressUtf16", testCompressUtf16),
        ("testCompressBase64", testCompressBase64),
        ("testEmojiBase64Compress", testEmojiBase64Compress),
        ("testCompressUri", testCompressUri),
        ("testCompressUInt8Array", testCompressUInt8Array),
        ("testDecompress", testDecompress),
        ("testEmojiDecompress", testEmojiDecompress),
        ("testDecompressUtf16", testDecompressUtf16),
        ("testEmojiBase64Decompress", testEmojiBase64Decompress),
        ("testDecompressBase64", testDecompressBase64),
        ("testDecompressUri", testDecompressUri),
        ("testDecompressUInt8Array", testDecompressUInt8Array),
        ("testCompressEmpty", testCompressEmpty),
        ("testDecompressEmpty", testDecompressEmpty),
        ("testCompressUTF16Empty", testCompressUTF16Empty),
        ("testDecompressUtf16", testDecompressUtf16),
        ("testCompressBase64Empty", testCompressBase64Empty),
        ("testDecompressBase64Empty", testDecompressBase64Empty),
        ("testCompressUriEmpty", testCompressUriEmpty),
        ("testDecompressUriEmpty", testDecompressUriEmpty),
        ("testCompressUInt8Empty", testCompressUInt8Empty),
        ("testDecompressUInt8Empty", testDecompressUInt8Empty),
    ]
}
