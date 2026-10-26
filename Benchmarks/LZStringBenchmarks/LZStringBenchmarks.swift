//
//  LZStringBenchmarks.swift
//  LZString
//
//  Created by mtakagi on 2026/03/29.
//

import Benchmark
import Foundation
import LZString

/// 計測対象のワークロードが成立していることを、**計測ループの外で**検証する。
///
/// `blackHole` は結果が最適化で捨てられるのを防ぐだけで、結果の妥当性は見ない。
/// 検証がないと、早期 return して空文字列を返すようになった実装が
/// 「高速化」として報告されてしまう (issue #46)。
///
/// Validates a workload outside the timed loop. `blackHole` prevents the result from
/// being optimised away but does not check it; without this, a decoder that started
/// returning early with an empty string would look like a speedup.
private func preflightLossless(_ label: String, input: String, decoded: String) {
    guard Array(decoded.utf16) == Array(input.utf16) else {
        fatalError("""
            ベンチマークの前提が成立していません / benchmark workload is not valid: \(label)
            input   : \(input.utf16.count) UTF-16 units
            decoded : \(decoded.utf16.count) UTF-16 units
            """)
    }
}

let benchmarks: @Sendable () -> Void = {
    // 可逆な形式で使う入力（445 UTF-16 units）
    // Input for the lossless formats (445 UTF-16 units).
    let text = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum."

    // 展開のベンチマーク用に事前に圧縮データを生成
    // Pre-calculate compressed data for decompression benchmarks
    let compressedData: Data = LZString.compress(input: text)
    let compressedBase64 = LZString.compressToBase64(input: text)
    let compressedUTF16 = LZString.compressToUTF16(input: text)
    let compressedUInt8Array = LZString.compressToUInt8Array(input: text)
    let compressedURI = LZString.compressToEncodedURIComponent(input: text)

    // --- 計測前の検証 / Preflight -------------------------------------------
    // 可逆な形式は、計測対象の入力が本当に完全復元できることを先に確かめる。
    preflightLossless("Data", input: text, decoded: LZString.decompress(input: compressedData))
    preflightLossless("Base64", input: text, decoded: LZString.decompressFromBase64(input: compressedBase64))
    preflightLossless("UTF16", input: text, decoded: LZString.decompressFromUTF16(input: compressedUTF16))
    preflightLossless("UInt8Array", input: text, decoded: LZString.decompressFromUInt8Array(input: compressedUInt8Array))
    preflightLossless("URI", input: text, decoded: LZString.decompressFromEncodedURIComponent(input: compressedURI))

    // 許容差は**正の値**で指定する。package-benchmark は内部で
    // `-threshold...threshold` の範囲を作って判定するため、負の値を渡すと
    // 範囲が逆転し、判定が成立しない（劣化を一切検出しなくなる）。
    // 劣化の向きは metric の polarity（throughput は prefersLarger）が扱う。
    //
    // Tolerances must be positive: package-benchmark builds `-threshold...threshold`
    // internally, so a negative value inverts the range and the gate stops detecting
    // anything. Direction is handled by the metric's polarity.
    //
    // ゲートは throughput p50 のみ。他の metric は情報として記録するが判定には使わない。
    // 壁時計時間とメモリは実行環境のノイズを拾いやすく、同一コードでも大きく振れる
    // （CI 実測で allocated resident memory が 40% 変動した）。
    //
    // Only throughput p50 gates. The others are recorded for information but not checked:
    // wall clock and memory swing widely even for identical code.
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
        // 1 回の操作を 1 サンプルとする。.kilo だと throughput が 1 桁台に量子化され
        // （CI 実測で 9 vs 8 = 11%）、5% 閾値が測定分解能を下回っていた。
        // One operation per sample: with .kilo the throughput values quantise to single
        // digits, putting the 5% threshold below the measurement resolution.
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
    // 非推奨の生 String 形式 (#22)。成功経路と失敗経路を分けて計測する。
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

/// 非推奨の生 `String` 形式 (#22) を計測する。
///
/// この形式は不可逆で、入力によっては展開が空文字列に終わる。
/// 他の形式と同じ 445 units の入力では**展開が必ず失敗する**ため、
/// 成功経路の計測には往復できる短い入力を使い、失敗経路は名前で明示して分ける。
/// 445 units の結果を他形式のスループットと並べて比較してはいけない。
///
/// Measures the deprecated raw `String` format. With the 445-unit input used by the other
/// formats, decoding always fails, so the successful-decode case uses a round-trippable
/// input and the failure path is named explicitly. The two are not comparable workloads.
@available(*, deprecated, message: "Intentional: measures the deprecated raw String format (#22) until it is removed.")
private func registerDeprecatedStringBenchmarks() {
    // 生 String 形式で往復できる入力（100 UTF-16 units）
    // Round-trippable through the raw String format (100 UTF-16 units).
    let roundTrippable = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore."
    let compressedRoundTrippable: String = LZString.compress(input: roundTrippable)

    // 成功経路であることを計測前に確認する。
    preflightLossless("String (round-trippable, 100 units)",
                      input: roundTrippable,
                      decoded: LZString.decompress(input: compressedRoundTrippable))

    // 失敗経路に使う入力（445 units）。サロゲートが U+FFFD に置換され展開は空になる。
    // The 445-unit input, whose surrogates are replaced with U+FFFD so decoding yields "".
    let lossyText = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum."
    let compressedLossy: String = LZString.compress(input: lossyText)

    // 失敗経路であり続けることを確認する（成功するようになったら名前が誤りになる）。
    precondition(LZString.decompress(input: compressedLossy).isEmpty,
                 "失敗経路のはずのベンチマークが成功している。名前と分類を見直すこと (#22, #46)")

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
