import Testing
import Foundation
@testable import LZString

/// Issue #58 — the byte-based fast path in the Base64 and URI decoders must be
/// indistinguishable from the `Character`-based path it replaces.
///
/// The fast path is only entered when byte offsets, `Character` offsets and UTF-16
/// offsets all coincide. Everything else falls back, so the public functions are expected
/// to agree with the original path for **every** input, valid or not.
@Suite("ASCII decoder fast path")
struct ASCIIFastPathTests {
    /// Payloads produced by the library, plus deliberately malformed and non-ASCII input.
    static var corpus: [String] {
        var inputs: [String] = []

        let texts = ["", "a", "aa", "hello world", "payload-100-xx",
                     "Lorem ipsum dolor sit amet, consectetur adipiscing elit",
                     "日本語🥺テスト", "e\u{0301}combining", "\u{FEFF}abc"]

        for text in texts {
            let base64 = LZString.compressToBase64(input: text)
            let uri = LZString.compressToEncodedURIComponent(input: text)
            inputs.append(base64)
            inputs.append(uri)

            // Every truncation of each payload.
            for n in 0...base64.count {
                inputs.append(String(base64.prefix(n)))
            }

            // CR, LF and CRLF at the front, middle and end: these take the fallback and
            // are the cases where byte counting and Character counting diverge.
            let middle = base64.count / 2
            for marker in ["\r", "\n", "\r\n"] {
                inputs.append(marker + base64)
                inputs.append(base64 + marker)
                inputs.append(String(base64.prefix(middle)) + marker + String(base64.dropFirst(middle)))
            }

            // Non-ASCII and alphabet-outside characters.
            for intruder in ["あ", "\u{FFFF}", "\u{0}", "~", "%", " ", "+"] {
                inputs.append(intruder + base64)
                inputs.append(base64 + intruder)
                inputs.append(String(base64.prefix(middle)) + intruder + String(base64.dropFirst(middle)))
            }
        }

        return inputs
    }

    /// The public Base64 decoder must agree with the `Character`-based path everywhere.
    @Test("Base64 fast path agrees with the Character path")
    func base64FastPathMatchesFallback() {
        for input in Self.corpus {
            let fast = LZString.decompressFromBase64(input: input)
            let slow = input.isEmpty ? "" : LZString._decompressFromBase64ByCharacter(input: input)

            #expect(Array(fast.utf16) == Array(slow.utf16),
                    "base64 \(input.debugDescription): fast=\(fast.debugDescription) slow=\(slow.debugDescription)")
        }
    }

    /// The same property for the URI decoder, including the space to '+' normalisation.
    @Test("URI fast path agrees with the Character path")
    func uriFastPathMatchesFallback() {
        for input in Self.corpus {
            let fast = LZString.decompressFromEncodedURIComponent(input: input)
            let slow = input.isEmpty ? "" : LZString._decompressFromEncodedURIComponentByCharacter(input: input)

            #expect(Array(fast.utf16) == Array(slow.utf16),
                    "uri \(input.debugDescription): fast=\(fast.debugDescription) slow=\(slow.debugDescription)")
        }
    }

    /// Pins which inputs the fast path accepts. CR is excluded because CR-LF is the one
    /// ASCII grapheme cluster spanning two scalars, which would shift every later index.
    @Test("The fast path guard accepts exactly the indexable inputs")
    func fastPathGuardIsExact() {
        #expect(LZString.asciiIndexableBytes("abcABC019+/=-$") != nil)
        #expect(LZString.asciiIndexableBytes(" ") != nil)
        #expect(LZString.asciiIndexableBytes("\n") != nil)
        #expect(LZString.asciiIndexableBytes("\u{0}") != nil)
        #expect(LZString.asciiIndexableBytes("\u{7F}") != nil)

        #expect(LZString.asciiIndexableBytes("\r") == nil)
        #expect(LZString.asciiIndexableBytes("\r\n") == nil)
        #expect(LZString.asciiIndexableBytes("a\r\nb") == nil)
        #expect(LZString.asciiIndexableBytes("あ") == nil)
        #expect(LZString.asciiIndexableBytes("🥺") == nil)
        #expect(LZString.asciiIndexableBytes("e\u{0301}") == nil)
    }

    /// Where the fast path is taken, byte offsets must equal Character and UTF-16 offsets.
    @Test("Accepted input indexes identically by byte, Character and UTF-16")
    func acceptedInputHasMatchingOffsets() {
        for input in Self.corpus where LZString.asciiIndexableBytes(input) != nil {
            #expect(input.utf8.count == input.count, "\(input.debugDescription): byte vs Character count")
            #expect(input.utf8.count == input.utf16.count, "\(input.debugDescription): byte vs UTF-16 count")
        }
    }

    /// URI input whose '+' became a space still decodes through the fast path.
    @Test("URI space normalisation still works on the fast path")
    func uriSpaceNormalisationOnFastPath() {
        let input = "payload-100-xx"
        let uri = LZString.compressToEncodedURIComponent(input: input)

        #expect(uri.contains("+"), "this vector must contain '+'")
        #expect(LZString.asciiIndexableBytes(uri) != nil, "the payload should take the fast path")

        let spaced = uri.replacingOccurrences(of: "+", with: " ")
        #expect(LZString.decompressFromEncodedURIComponent(input: spaced) == input)
    }
}
