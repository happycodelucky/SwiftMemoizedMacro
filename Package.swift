// swift-tools-version: 6.0

import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "Memoized",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(
            name: "Memoized",
            targets: ["Memoized"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "602.0.0"),
    ],
    targets: [
        // The macro implementation — runs at compile time
        .macro(
            name: "MemoizedMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),
        // The public API — what consumers import
        .target(
            name: "Memoized",
            dependencies: ["MemoizedMacros"]
        ),
        // Tests
        .testTarget(
            name: "MemoizedTests",
            dependencies: [
                "Memoized",
                "MemoizedMacros",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ]
        ),
    ]
)
