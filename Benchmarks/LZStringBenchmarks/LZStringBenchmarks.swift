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
    // Only throughput p50 gates. The others are recorded for information but not checked:
    // wall clock and memory swing widely even for identical code.
    //
    // The tolerance is 15%. Throughput percentiles are stored as integers after unit
    // normalisation, so a one- or two-unit jitter in p50 is already several percent:
    // at a stored 39K one unit is 2.6% and two are 5.1%; at 23K one unit is 4.3% and two
    // are 8.7%. At 5% an unchanged tree failed two runs out of three (by 5% and 7%), so
    // 15% clears the quantisation ceiling and the observed noise while still catching
    // real regressions (an injected one measured 41%).
    let thresholds: [BenchmarkMetric: BenchmarkThresholds] = [
        .throughput: BenchmarkThresholds(relative: [.p50: 15.0]),
        .wallClock: BenchmarkThresholds(relative: [:], absolute: [:]),
        .mallocCountTotal: BenchmarkThresholds(relative: [:], absolute: [:]),
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

    Benchmark("Decompress (Base64, short)") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(LZString.decompressFromBase64(input: shortBase64))
        }
    }
    Benchmark("Decompress (Base64, Unicode source)") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(LZString.decompressFromBase64(input: unicodeBase64))
        }
    }
    Benchmark("Decompress (URI, short)") { benchmark in
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
