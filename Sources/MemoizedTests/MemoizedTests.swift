import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

#if canImport(MemoizedMacros)
import MemoizedMacros

let testMacros: [String: Macro.Type] = [
    "Memoizable": MemoizableMacro.self,
    "memoized": MemoizedExprMacro.self,
]
#endif

// MARK: - @Memoizable Macro Tests

final class MemoizableMacroExpansionTests: XCTestCase {

    func testMemoizableGeneratesStorage() throws {
        #if canImport(MemoizedMacros)
        assertMacroExpansion(
            """
            @Memoizable
            class Theme {
                var colorScheme: String = "dark"
            }
            """,
            expandedSource: """
            class Theme {
                var colorScheme: String = "dark"

                private let _memoized = MemoizedStorage()
            }
            """,
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testMemoizableOnStruct() throws {
        #if canImport(MemoizedMacros)
        assertMacroExpansion(
            """
            @Memoizable
            struct Settings {
                var threshold: Int = 10
            }
            """,
            expandedSource: """
            struct Settings {
                var threshold: Int = 10

                private let _memoized = MemoizedStorage()
            }
            """,
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
}

// MARK: - #memoized Expression Macro Tests

final class MemoizedExprMacroExpansionTests: XCTestCase {

    func testSingleDependencyExpansion() throws {
        #if canImport(MemoizedMacros)
        assertMacroExpansion(
            """
            class Theme {
                var colorScheme: String = "dark"
                var style: String {
                    #memoized(\\Self.colorScheme) {
                        "hello \\(self.colorScheme)"
                    }
                }
            }
            """,
            expandedSource: """
            class Theme {
                var colorScheme: String = "dark"
                var style: String {
                    _memoized.memoize(for: "colorScheme", deps: self.colorScheme) {
                        "hello \\(self.colorScheme)"
                    }
                }
            }
            """,
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testMultipleDependenciesExpansion() throws {
        #if canImport(MemoizedMacros)
        assertMacroExpansion(
            """
            class Theme {
                var colorScheme: String = "dark"
                var fontSize: Double = 14.0
                var palette: String {
                    #memoized(\\Self.colorScheme, \\Self.fontSize) {
                        "\\(self.colorScheme)-\\(self.fontSize)"
                    }
                }
            }
            """,
            expandedSource: """
            class Theme {
                var colorScheme: String = "dark"
                var fontSize: Double = 14.0
                var palette: String {
                    _memoized.memoize(for: "colorScheme,fontSize", deps: Deps2(self.colorScheme, self.fontSize)) {
                        "\\(self.colorScheme)-\\(self.fontSize)"
                    }
                }
            }
            """,
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testStructExpansion() throws {
        #if canImport(MemoizedMacros)
        assertMacroExpansion(
            """
            struct Settings {
                var threshold: Int = 10
                var label: String {
                    #memoized(\\Self.threshold) {
                        "Threshold: \\(self.threshold)"
                    }
                }
            }
            """,
            expandedSource: """
            struct Settings {
                var threshold: Int = 10
                var label: String {
                    _memoized.memoize(for: "threshold", deps: self.threshold) {
                        "Threshold: \\(self.threshold)"
                    }
                }
            }
            """,
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    // MARK: - Diagnostics

    func testErrorOnMissingDeps() throws {
        #if canImport(MemoizedMacros)
        assertMacroExpansion(
            """
            class Foo {
                var value: Int {
                    #memoized() {
                        42
                    }
                }
            }
            """,
            expandedSource: """
            class Foo {
                var value: Int {
                    #memoized() {
                        42
                    }
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "#memoized requires at least one dependency key path", line: 3, column: 9),
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

final class MemoizedStorageTests: XCTestCase {

    func testBoxCreation() {
        let storage = MemoizedStorage()
        let box1: MemoizedBox<Int> = storage.box(for: "a")
        let box2: MemoizedBox<Int> = storage.box(for: "a")
        // Same key returns the same box
        box1.store(value: 42, deps: "x")
        XCTAssertEqual(box2.value(for: "x"), 42)
    }

    func testDifferentKeysAreSeparate() {
        let storage = MemoizedStorage()
        let boxA: MemoizedBox<Int> = storage.box(for: "a")
        let boxB: MemoizedBox<Int> = storage.box(for: "b")
        boxA.store(value: 1, deps: "x")
        XCTAssertNil(boxB.value(for: "x"))
    }
}

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
        let box = MemoizedBox<String>()
        let deps = Deps2("dark", 14.0)
        box.store(value: "cached", deps: deps)
        XCTAssertEqual(box.value(for: Deps2("dark", 14.0)), "cached")
        XCTAssertNil(box.value(for: Deps2("dark", 16.0)))
        XCTAssertNil(box.value(for: Deps2("light", 14.0)))
    }

    func testCacheInvalidation() {
        let box = MemoizedBox<Int>()
        box.store(value: 1, deps: "dark")
        XCTAssertEqual(box.value(for: "dark"), 1)

        box.store(value: 2, deps: "light")
        XCTAssertNil(box.value(for: "dark"))
        XCTAssertEqual(box.value(for: "light"), 2)
    }

    // MARK: - Struct Integration

    func testNonMutatingGetterOnStruct() {
        struct Counter {
            var input: Int
            private let _memoized = MemoizedStorage()

            var doubled: Int {
                let _box: MemoizedBox<Int> = _memoized.box(for: "doubled")
                let deps = input
                if let cached = _box.value(for: deps) {
                    return cached
                }
                let value = input * 2
                _box.store(value: value, deps: deps)
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
            let storage = MemoizedStorage()
        }

        let a = Wrapper(dep: "x")
        let box: MemoizedBox<Int> = a.storage.box(for: "test")
        box.store(value: 42, deps: "x")

        // Copy shares the same storage reference
        let b = a
        let boxB: MemoizedBox<Int> = b.storage.box(for: "test")
        XCTAssertEqual(boxB.value(for: "x"), 42)
    }
}

final class DepsWrapperTests: XCTestCase {

    func testDeps2Equality() {
        XCTAssertEqual(Deps2("a", 1), Deps2("a", 1))
        XCTAssertNotEqual(Deps2("a", 1), Deps2("b", 1))
        XCTAssertNotEqual(Deps2("a", 1), Deps2("a", 2))
    }

    func testDeps3Equality() {
        XCTAssertEqual(Deps3("a", 1, true), Deps3("a", 1, true))
        XCTAssertNotEqual(Deps3("a", 1, true), Deps3("a", 1, false))
    }

    func testDeps4Equality() {
        XCTAssertEqual(Deps4("a", 1, true, 3.14), Deps4("a", 1, true, 3.14))
        XCTAssertNotEqual(Deps4("a", 1, true, 3.14), Deps4("a", 1, true, 2.71))
    }
}

// MARK: - Macro Integration Tests (actual macro compilation)

@Memoizable
class TestTheme {
    var colorScheme: String = "dark"

    var style: String {
        #memoized(\Self.colorScheme) {
            "style-\(self.colorScheme)"
        }
    }
}

final class MacroIntegrationTests: XCTestCase {

    func testMemoizedMacroCompiles() {
        let theme = TestTheme()
        XCTAssertEqual(theme.style, "style-dark")
    }

    func testMemoizedMacroCaches() {
        let theme = TestTheme()
        let first = theme.style
        let second = theme.style
        XCTAssertEqual(first, second)
    }

    func testMemoizedMacroInvalidatesOnChange() {
        let theme = TestTheme()
        XCTAssertEqual(theme.style, "style-dark")
        theme.colorScheme = "light"
        XCTAssertEqual(theme.style, "style-light")
    }
}
