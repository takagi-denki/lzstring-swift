//
//  LZStringBenchmarks.swift
//  LZString
//
//  Created by mtakagi on 2026/03/29.
//

import Benchmark
import Foundation
import LZString

let benchmarks: @Sendable () -> Void = {
    // テスト用のダミー文字列 / Dummy string for testing
    let text = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum."
    
    // 展開のベンチマーク用に事前に圧縮データを生成
    // Pre-calculate compressed data for decompression benchmarks
    let compressedData: Data = LZString.compress(input: text)
    let compressedString: String = LZString.compress(input: text)
    let compressedBase64 = LZString.compressToBase64(input: text)
    let compressedUTF16 = LZString.compressToUTF16(input: text)
    let compressedUInt8Array = LZString.compressToUInt8Array(input: text)
    let compressedURI = LZString.compressToEncodedURIComponent(input: text)
    
    let thresholds: [BenchmarkMetric: BenchmarkThresholds] = [
        .throughput: BenchmarkThresholds(relative: [.p50: -5.0])
//        .mallocCountTotal: BenchmarkThresholds(absolute: [.p50: 0])
    ]
    
    // ベンチマークの基本設定 / Default configuration for benchmarks
    Benchmark.defaultConfiguration = .init(
        metrics: [.wallClock, .throughput, .mallocCountTotal, .allocatedResidentMemory],
        warmupIterations: 10,
        scalingFactor: .kilo, // 1000回ループで1回の測定とする / 1000 iterations per measurement
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
    Benchmark("Compress (String)") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(LZString.compress(input: text) as String)
        }
    }
    Benchmark("Decompress (String)") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(LZString.decompress(input: compressedString))
        }
    }

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
