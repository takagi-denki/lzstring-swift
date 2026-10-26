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
    let compressedBase64 = LZString.compressToBase64(input: text)
    let compressedUTF16 = LZString.compressToUTF16(input: text)
    let compressedUInt8Array = LZString.compressToUInt8Array(input: text)
    let compressedURI = LZString.compressToEncodedURIComponent(input: text)
    
    // 許容差は**正の値**で指定する。package-benchmark は内部で
    // `-threshold...threshold` の範囲を作って判定するため、負の値を渡すと
    // 範囲が逆転し、判定が成立しない（劣化を一切検出しなくなる）。
    // 劣化の向きは metric の polarity（throughput は prefersLarger）が扱うので、
    // 「throughput が 5% 以上落ちたら失敗」は正の 5.0 で表現する。
    //
    // Tolerances must be positive: package-benchmark builds `-threshold...threshold`
    // internally, so a negative value inverts the range and the gate stops detecting
    // anything. Direction is handled by the metric's polarity.
    // ゲートは throughput p50 のみ。他の metric は情報として記録するが判定には使わない。
    // 壁時計時間とメモリは実行環境のノイズを拾いやすく、同一コードでも大きく振れる
    // （CI 実測で allocated resident memory が 40% 変動した）。
    //
    // Only throughput p50 gates. The other metrics are recorded for information but not
    // checked: wall clock and memory are environment-sensitive and swing widely even for
    // identical code (allocated resident memory moved 40% between CI runs).
    let thresholds: [BenchmarkMetric: BenchmarkThresholds] = [
        .throughput: BenchmarkThresholds(relative: [.p50: 5.0]),
        .wallClock: BenchmarkThresholds(relative: [:], absolute: [:]),
        .mallocCountTotal: BenchmarkThresholds(relative: [:], absolute: [:]),
        .allocatedResidentMemory: BenchmarkThresholds(relative: [:], absolute: [:]),
    ]
    
    // ベンチマークの基本設定 / Default configuration for benchmarks
    Benchmark.defaultConfiguration = .init(
        metrics: [.wallClock, .throughput, .mallocCountTotal, .allocatedResidentMemory],
        warmupIterations: 10,
        scalingFactor: .one, // 1 回の操作を 1 サンプルとする（分解能を上げる） / one operation per sample
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
    // 非推奨の生 String 形式 (#22)。削除するまでは計測対象として残す。
    // The deprecated raw String format (#22) stays measured until it is removed.
    registerDeprecatedStringBenchmarks(text: text)

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

@available(*, deprecated, message: "Intentional: measures the deprecated raw String format (#22) until it is removed.")
private func registerDeprecatedStringBenchmarks(text: String) {
    let compressedString: String = LZString.compress(input: text)

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
}
