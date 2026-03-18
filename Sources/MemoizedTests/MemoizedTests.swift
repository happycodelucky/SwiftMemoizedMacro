import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

#if canImport(MemoizedMacros)
import MemoizedMacros

let testMacros: [String: Macro.Type] = [
    "Memoized": MemoizedMacro.self,
]
#endif

final class MemoizedMacroExpansionTests: XCTestCase {

    // MARK: - Single Dependency Expansion

    func testSingleDependencyExpansion() throws {
        #if canImport(MemoizedMacros)
        assertMacroExpansion(
            """
            class Theme {
                var colorMode: String = "dark"

                @Memoized(\\.colorMode)
                var palette: [String] = generatePalette(colorMode)
            }
            """,
            expandedSource: """
            class Theme {
                var colorMode: String = "dark"
                var palette: [String] {
                    get {
                        let deps = self.colorMode
                        if let cached = _memoized_palette.value(for: deps) {
                            return cached
                        }
                        let value = generatePalette(colorMode)
                        _memoized_palette.store(value: value, deps: deps)
                        return value
                    }
                }

                private let _memoized_palette = MemoizedBox<[String]>()
            }
            """,
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    // MARK: - Multiple Dependencies Expansion

    func testMultipleDependenciesExpansion() throws {
        #if canImport(MemoizedMacros)
        assertMacroExpansion(
            """
            class Theme {
                var colorMode: String = "dark"
                var fontSize: Double = 14.0

                @Memoized(\\.colorMode, \\.fontSize)
                var style: String = "\\(colorMode)-\\(fontSize)"
            }
            """,
            expandedSource: """
            class Theme {
                var colorMode: String = "dark"
                var fontSize: Double = 14.0
                var style: String {
                    get {
                        let deps = (self.colorMode, self.fontSize)
                        if let cached = _memoized_style.value(for: deps) {
                            return cached
                        }
                        let value = "\\(colorMode)-\\(fontSize)"
                        _memoized_style.store(value: value, deps: deps)
                        return value
                    }
                }

                private let _memoized_style = MemoizedBox<String>()
            }
            """,
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    // MARK: - Struct Expansion

    func testStructExpansion() throws {
        #if canImport(MemoizedMacros)
        assertMacroExpansion(
            """
            struct Settings {
                var threshold: Int = 10

                @Memoized(\\.threshold)
                var label: String = "Threshold: \\(threshold)"
            }
            """,
            expandedSource: """
            struct Settings {
                var threshold: Int = 10
                var label: String {
                    get {
                        let deps = self.threshold
                        if let cached = _memoized_label.value(for: deps) {
                            return cached
                        }
                        let value = "Threshold: \\(threshold)"
                        _memoized_label.store(value: value, deps: deps)
                        return value
                    }
                }

                private let _memoized_label = MemoizedBox<String>()
            }
            """,
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    // MARK: - Diagnostics

    func testErrorOnComputedProperty() throws {
        #if canImport(MemoizedMacros)
        assertMacroExpansion(
            """
            class Foo {
                @Memoized(\\.x)
                var value: Int {
                    42
                }
            }
            """,
            expandedSource: """
            class Foo {
                var value: Int {
                    42
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "@Memoized requires a stored property with an initializer expression", line: 2, column: 5),
            ],
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testErrorOnMissingDeps() throws {
        #if canImport(MemoizedMacros)
        assertMacroExpansion(
            """
            class Foo {
                @Memoized()
                var value: Int = 42
            }
            """,
            expandedSource: """
            class Foo {
                var value: Int = 42
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "@Memoized requires at least one dependency key path", line: 2, column: 5),
            ],
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
}

// MARK: - Runtime Behavior Tests

import Memoized

final class MemoizedBoxTests: XCTestCase {

    func testCacheHit() {
        let box = MemoizedBox<Int>()
        box.store(value: 42, deps: "dark")
        XCTAssertEqual(box.value(for: "dark"), 42)
    }

    func testCacheMiss() {
        let box = MemoizedBox<Int>()
        box.store(value: 42, deps: "dark")
        XCTAssertNil(box.value(for: "light"))
    }

    func testEmptyBox() {
        let box = MemoizedBox<Int>()
        XCTAssertNil(box.value(for: "dark"))
    }

    func testMultipleDeps() {
        struct Pair: Equatable {
            let mode: String
            let size: Double
        }
        let box = MemoizedBox<String>()
        box.store(value: "cached", deps: Pair(mode: "dark", size: 14.0))
        XCTAssertEqual(box.value(for: Pair(mode: "dark", size: 14.0)), "cached")
        XCTAssertNil(box.value(for: Pair(mode: "dark", size: 16.0)))
        XCTAssertNil(box.value(for: Pair(mode: "light", size: 14.0)))
    }

    func testRestore() {
        let box = MemoizedBox<Int>()
        box.store(value: 1, deps: "dark")
        XCTAssertEqual(box.value(for: "dark"), 1)

        // Simulate invalidation + recompute
        box.store(value: 2, deps: "light")
        XCTAssertNil(box.value(for: "dark"))
        XCTAssertEqual(box.value(for: "light"), 2)
    }

    // MARK: - Struct Integration

    func testNonMutatingGetterOnStruct() {
        struct Counter {
            var input: Int
            private let _memoized_doubled = MemoizedBox<Int>()

            var doubled: Int {
                let deps = input
                if let cached = _memoized_doubled.value(for: deps) {
                    return cached
                }
                let value = input * 2
                _memoized_doubled.store(value: value, deps: deps)
                return value
            }
        }

        let counter = Counter(input: 5)
        XCTAssertEqual(counter.doubled, 10)
        // Second access should hit the cache
        XCTAssertEqual(counter.doubled, 10)
    }

    func testStructCopySharesCache() {
        struct Wrapper {
            var dep: String
            let box = MemoizedBox<Int>()
        }

        let a = Wrapper(dep: "x")
        a.box.store(value: 42, deps: "x")

        // Copy shares the same box reference
        let b = a
        XCTAssertEqual(b.box.value(for: "x"), 42)

        // Mutating through one copy is visible to the other
        b.box.store(value: 99, deps: "y")
        XCTAssertEqual(a.box.value(for: "y"), 99)
    }
}
