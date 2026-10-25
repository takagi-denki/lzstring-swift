// swift-tools-version:6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// package-benchmark の command plugin は Windows をサポートしておらず、
// コンパイル時に #error("Unsupported Platform") で失敗する。
// `swift test` はパッケージのプラグインもコンパイルするため、除外しないと
// Windows ではテスト自体が実行できない。ライブラリ本体は Windows でも動く。
//
// package-benchmark's command plugin does not support Windows and fails to compile
// there. `swift test` compiles package plugins, so the benchmark target is excluded
// on Windows; the library itself builds and runs there.
#if os(Windows)
let benchmarkDependencies: [Package.Dependency] = []
let benchmarkTargets: [Target] = []
#else
let benchmarkDependencies: [Package.Dependency] = [
    .package(url: "https://github.com/ordo-one/package-benchmark", exact: "1.31.0"),
]
let benchmarkTargets: [Target] = [
    .executableTarget(
        name: "LZStringBenchmarks",
        dependencies: [
            "LZString",
            .product(name: "Benchmark", package: "package-benchmark")
        ],
        path: "Benchmarks/LZStringBenchmarks",
        plugins: [
            .plugin(name: "BenchmarkPlugin", package: "package-benchmark")
        ]
    )
]
#endif

let package = Package(
    name: "LZString",
    platforms: [.macOS(.v13), .iOS(.v13), .tvOS(.v13), .watchOS(.v6)],
    products: [
        // Products define the executables and libraries produced by a package, and make them visible to other packages.
        .library(
            name: "LZString",
            targets: ["LZString"]),
    ],
    dependencies: benchmarkDependencies,
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(
            name: "LZString",
            dependencies: []),
        .testTarget(
            name: "LZStringTests",
            dependencies: ["LZString"]),
    ] + benchmarkTargets
)
