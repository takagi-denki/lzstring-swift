//
//  LZStringBenchmarks.swift
//  LZString
//
//  Created by mtakagi on 2026/03/29.
//

import Benchmark
import Foundation
import LZString

/// Validates a workload outside the timed loop. `blackHole` prevents the result from
/// being optimised away but does not check it; without this, a decoder that started
/// returning early with an empty string would look like a speedup.
private func preflightLossless(_ label: String, input: String, decoded: String) {
    guard Array(decoded.utf16) == Array(input.utf16) else {
        fatalError("""
            Benchmark workload is not valid: \(label)
            input   : \(input.utf16.count) UTF-16 units
            decoded : \(decoded.utf16.count) UTF-16 units
            """)
    }
}

let benchmarks: @Sendable () -> Void = {
    // Input for the lossless formats (445 UTF-16 units).
    let text = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum."

    // Pre-calculate compressed data for the decompression benchmarks.
    let compressedData: Data = LZString.compress(input: text)
    let compressedBase64 = LZString.compressToBase64(input: text)
    let compressedUTF16 = LZString.compressToUTF16(input: text)
    let compressedUInt8Array = LZString.compressToUInt8Array(input: text)
    let compressedURI = LZString.compressToEncodedURIComponent(input: text)

    // --- Preflight -----------------------------------------------------------
    // For the lossless formats, confirm up front that the measured input really does
    // decode back to itself.
    preflightLossless("Data", input: text, decoded: LZString.decompress(input: compressedData))
    preflightLossless("Base64", input: text, decoded: LZString.decompressFromBase64(input: compressedBase64))
    preflightLossless("UTF16", input: text, decoded: LZString.decompressFromUTF16(input: compressedUTF16))
    preflightLossless("UInt8Array", input: text, decoded: LZString.decompressFromUInt8Array(input: compressedUInt8Array))
    preflightLossless("URI", input: text, decoded: LZString.decompressFromEncodedURIComponent(input: compressedURI))

    // Tolerances must be positive: package-benchmark builds `-threshold...threshold`
    // internally, so a negative value inverts the range and the gate stops detecting
    // anything. Direction is handled by the metric's polarity.
    //
    // Only `mallocCountTotal` gates. It is the one metric here that is deterministic:
    // identical code allocates an identical number of times, so the gate cannot fire on
    // measurement noise.
    //
    // Throughput used to gate at 15% and no longer does (issue #87). The workflow measures
    // the baseline and the candidate sequentially in one job, and the second measurement is
    // systematically lower: a comment-only commit, compiling to code identical to main,
    // was reported as 18-29% worse on 9 of 18 benchmarks. That bias is larger than any
    // tolerance that would still catch a real regression, and it is not the quantisation
    // problem from #56 either, since it showed up at a stored value of 7279 where one unit
    // is 0.014%. Throughput, wall clock and memory are recorded for information; measure
    // them locally with `swift package benchmark`, where the comparison is stable.
    //
    // Both a relative and an absolute tolerance are set, and package-benchmark evaluates
    // them independently, so either one firing is a deviation. The relative tolerance is
    // what catches an algorithmic regression, which shows up as a multiple rather than a
    // few percent: restoring the phrase-keyed compressor dictionary moves a malloc count
    // from 17 back to 907. The absolute tolerance covers the case the relative one cannot,
    // where the baseline count is 0 and package-benchmark reports a relative difference of
    // 0 to avoid dividing by zero.
    let thresholds: [BenchmarkMetric: BenchmarkThresholds] = [
        .mallocCountTotal: BenchmarkThresholds(relative: [.p50: 25.0], absolute: [.p50: 50]),
        .throughput: BenchmarkThresholds(relative: [:], absolute: [:]),
        .wallClock: BenchmarkThresholds(relative: [:], absolute: [:]),
        .allocatedResidentMemory: BenchmarkThresholds(relative: [:], absolute: [:]),
    ]
    
    // Default configuration for the benchmarks.
    Benchmark.defaultConfiguration = .init(
        metrics: [.wallClock, .throughput, .mallocCountTotal, .allocatedResidentMemory],
        warmupIterations: 10,
        // One operation per sample. With .kilo the throughput quantised to single digits
        // (9 vs 8 = 11% in CI), putting the 5% threshold below the measurement resolution.
        scalingFactor: .one,
        maxDuration: .seconds(1),
        maxIterations: 10_000,
        thresholds: thresholds
    )

    // --- Data ---
    Benchmark("Compress (Data)") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(LZString.compress(input: text) as Data)
        }
    }
    Benchmark("Decompress (Data)") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(LZString.decompress(input: compressedData))
        }
    }

    // --- String ---
    // The deprecated raw String format (#22), measured as separate success and failure paths.
    registerDeprecatedStringBenchmarks()

    // --- Base64 ---
    Benchmark("Compress (Base64)") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(LZString.compressToBase64(input: text))
        }
    }
    Benchmark("Decompress (Base64)") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(LZString.decompressFromBase64(input: compressedBase64))
        }
    }

    // --- UTF16 ---
    Benchmark("Compress (UTF16)") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(LZString.compressToUTF16(input: text))
        }
    }
    Benchmark("Decompress (UTF16)") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(LZString.decompressFromUTF16(input: compressedUTF16))
        }
    }
    
    // --- UInt8Array ---
    Benchmark("Compress (UInt8Array)") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(LZString.compressToUInt8Array(input: text))
        }
    }
    Benchmark("Decompress (UInt8Array)") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(LZString.decompressFromUInt8Array(input: compressedUInt8Array))
        }
    }

    // --- Large, poorly compressible payload (issue #59) ---
    // Output size is close to input size here, so the intermediate buffers that the
    // UInt8Array path used to allocate are at their most expensive. Generated with a
    // fixed LCG so the workload is identical between runs.
    let incompressible: String = {
        var state: UInt64 = 0x9E3779B97F4A7C15
        var text = ""
        text.reserveCapacity(4000)
        for _ in 0..<4000 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            text.append(Character(UnicodeScalar(32 + UInt8(truncatingIfNeeded: state >> 33) % 95)))
        }
        return text
    }()

    preflightLossless("UInt8Array (large incompressible)",
                      input: incompressible,
                      decoded: LZString.decompressFromUInt8Array(input: LZString.compressToUInt8Array(input: incompressible)))

    Benchmark("Compress (UInt8Array, large incompressible)") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(LZString.compressToUInt8Array(input: incompressible))
        }
    }

    // Base64 and URI emit one ASCII symbol per six bits of output, so the per-symbol cost
    // dominates when the payload barely compresses (issue #77). The 445-unit text measured
    // above is the typical-input shape, where output volume is much lower.
    preflightLossless("Base64 (large incompressible)",
                      input: incompressible,
                      decoded: LZString.decompressFromBase64(input: LZString.compressToBase64(input: incompressible)))
    preflightLossless("URI (large incompressible)",
                      input: incompressible,
                      decoded: LZString.decompressFromEncodedURIComponent(input: LZString.compressToEncodedURIComponent(input: incompressible)))

    Benchmark("Compress (Base64, large incompressible)") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(LZString.compressToBase64(input: incompressible))
        }
    }

    Benchmark("Compress (URI, large incompressible)") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(LZString.compressToEncodedURIComponent(input: incompressible))
        }
    }

    // --- ASCII decoder payload shapes (issue #58) ---
    // The 445-unit case above is the large ASCII payload; these add a short payload and
    // one whose source text is Unicode, so the decoder's output work differs.
    let shortText = "hello world"
    let unicodeText = String(repeating: "日本語🥺テスト", count: 40)
    let shortBase64 = LZString.compressToBase64(input: shortText)
    let unicodeBase64 = LZString.compressToBase64(input: unicodeText)
    let shortURI = LZString.compressToEncodedURIComponent(input: shortText)

    preflightLossless("Base64 (short)", input: shortText, decoded: LZString.decompressFromBase64(input: shortBase64))
    preflightLossless("Base64 (Unicode source)", input: unicodeText, decoded: LZString.decompressFromBase64(input: unicodeBase64))
    preflightLossless("URI (short)", input: shortText, decoded: LZString.decompressFromEncodedURIComponent(input: shortURI))

    // Short payloads measure a few microseconds per sample and swing by about 20% between
    // runs of identical code, so their timings are not gated (issues #58 and #71). Their
    // malloc counts are as deterministic as any other benchmark's and stay gated (issue
    // #89); the name says what is exempt, so an allocation regression on a short path is
    // not silently ignored.
    //
    // The absolute tolerance is tightened from the default 50 because these counts are
    // small — 10 for the compression benchmark and 23 for the three decoder ones — and 50
    // would permit any change at all. The relative tolerance binds below a count of 20 and
    // the absolute one above it, so at the measured counts the smallest increase that fails
    // is 3 and 6 respectively. Both still absorb an incidental one- or two-allocation
    // change, which is as tight as is useful for a metric that does not drift on its own.
    var timingsNotGated = Benchmark.defaultConfiguration
    timingsNotGated.thresholds = [
        .mallocCountTotal: BenchmarkThresholds(relative: [.p50: 25.0], absolute: [.p50: 5]),
        .throughput: BenchmarkThresholds(relative: [:], absolute: [:]),
        .wallClock: BenchmarkThresholds(relative: [:], absolute: [:]),
        .allocatedResidentMemory: BenchmarkThresholds(relative: [:], absolute: [:]),
    ]

    Benchmark("Decompress (Base64, short)", configuration: timingsNotGated) { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(LZString.decompressFromBase64(input: shortBase64))
        }
    }
    Benchmark("Decompress (Base64, Unicode source)") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(LZString.decompressFromBase64(input: unicodeBase64))
        }
    }
    // Short UTF-16 payload: checks that materialising the code units up front (issue #74)
    // does not cost more than it saves on tiny inputs.
    let shortUTF16 = LZString.compressToUTF16(input: shortText)
    preflightLossless("UTF16 (short)", input: shortText, decoded: LZString.decompressFromUTF16(input: shortUTF16))

    Benchmark("Decompress (UTF16, short)", configuration: timingsNotGated) { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(LZString.decompressFromUTF16(input: shortUTF16))
        }
    }

    Benchmark("Decompress (URI, short)", configuration: timingsNotGated) { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(LZString.decompressFromEncodedURIComponent(input: shortURI))
        }
    }

    // --- URI Component ---
    Benchmark("Compress (URI)") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(LZString.compressToEncodedURIComponent(input: text))
        }
    }
    Benchmark("Decompress (URI)") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(LZString.decompressFromEncodedURIComponent(input: compressedURI))
        }
    }

    // --- Compressor input shapes (issue #34) ---------------------------------------
    // Everything above compresses the same 445-unit Latin paragraph, which keeps phrases
    // short. The compressor's phrase lookup is where cost grows with phrase length, so
    // these add the shapes that make phrases long or the dictionary deep.

    // 64 Ki units of a repeating pattern: the phrases here grow to hundreds of units.
    let repeated = String(repeating: "abcd", count: 16384)

    // Structured text with a repeating key vocabulary, generated with a fixed LCG so the
    // workload is identical between runs.
    let jsonLike: String = {
        var state: UInt64 = 7
        var parts = [String]()
        parts.reserveCapacity(2000)
        for index in 0..<2000 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let value = Int((state >> 33) % 1000)
            parts.append("{\"id\":\(index),\"name\":\"item-\(value)\",\"active\":\(value % 2 == 0)}")
        }
        return "{\"items\":[" + parts.joined(separator: ",") + "]}"
    }()

    // Non-ASCII BMP text mixed with surrogate pairs, so a phrase boundary can fall between
    // the two halves of one emoji.
    let unicodeMix = String(repeating: "日本語のテキスト😀🥺e\u{301}", count: 2000)

    // A short message, to show the change does not cost anything on tiny inputs.
    let shortMessage = "hello world"

    preflightLossless("Base64 (64Ki repeated)", input: repeated,
                      decoded: LZString.decompressFromBase64(input: LZString.compressToBase64(input: repeated)))
    preflightLossless("Base64 (JSON-like)", input: jsonLike,
                      decoded: LZString.decompressFromBase64(input: LZString.compressToBase64(input: jsonLike)))
    preflightLossless("Base64 (Unicode mix)", input: unicodeMix,
                      decoded: LZString.decompressFromBase64(input: LZString.compressToBase64(input: unicodeMix)))
    preflightLossless("Base64 (short message)", input: shortMessage,
                      decoded: LZString.decompressFromBase64(input: LZString.compressToBase64(input: shortMessage)))

    Benchmark("Compress (Base64, 64Ki repeated)") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(LZString.compressToBase64(input: repeated))
        }
    }

    Benchmark("Compress (Base64, JSON-like)") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(LZString.compressToBase64(input: jsonLike))
        }
    }

    Benchmark("Compress (Base64, Unicode mix)") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(LZString.compressToBase64(input: unicodeMix))
        }
    }

    // Like the short decoder benchmarks above: the timing is not gated, the allocation
    // count is.
    Benchmark("Compress (Base64, short message)", configuration: timingsNotGated) { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(LZString.compressToBase64(input: shortMessage))
        }
    }
}

/// Measures the deprecated raw `String` format (#22). With the 445-unit input used by the other
/// formats, decoding always fails, so the successful-decode case uses a round-trippable
/// input and the failure path is named explicitly. The two are not comparable workloads.
@available(*, deprecated, message: "Intentional: measures the deprecated raw String format (#22) until it is removed.")
private func registerDeprecatedStringBenchmarks() {
    // Round-trippable through the raw String format (100 UTF-16 units).
    let roundTrippable = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore."
    let compressedRoundTrippable: String = LZString.compress(input: roundTrippable)

    // Confirm this really is the success path before measuring it.
    preflightLossless("String (round-trippable, 100 units)",
                      input: roundTrippable,
                      decoded: LZString.decompress(input: compressedRoundTrippable))

    // The 445-unit input, whose surrogates are replaced with U+FFFD so decoding yields "".
    let lossyText = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum."
    let compressedLossy: String = LZString.compress(input: lossyText)

    // Confirm it remains a failure path; if it started succeeding the name would be wrong.
    precondition(LZString.decompress(input: compressedLossy).isEmpty,
                 "A benchmark labelled as the failure path is succeeding; revisit its name and classification (#22, #46)")

    Benchmark("Compress (String, 100 units)") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(LZString.compress(input: roundTrippable) as String)
        }
    }
    Benchmark("Decompress (String, 100 units)") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(LZString.decompress(input: compressedRoundTrippable))
        }
    }
    Benchmark("Decompress (String, lossy failure path)") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(LZString.decompress(input: compressedLossy))
        }
    }
}
