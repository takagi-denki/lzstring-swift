// swift-tools-version:6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "LZString",
    platforms: [.macOS(.v13), .iOS(.v13), .tvOS(.v13), .watchOS(.v6)],
    products: [
        // Products define the executables and libraries produced by a package, and make them visible to other packages.
        .library(
            name: "LZString",
            targets: ["LZString"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ordo-one/package-benchmark", exact: "1.31.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(
            name: "LZString",
            dependencies: []),
        .testTarget(
            name: "LZStringTests",
            dependencies: ["LZString"]),
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
)
