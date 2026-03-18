// MARK: - Macro Declarations

/// Adds memoization storage to a class or struct.
///
/// Apply to a type that contains properties using `#memoized`. This macro
/// generates a `private let _memoized = MemoizedStorage()` member that
/// serves as shared backing storage for all `#memoized` properties.
///
/// Works with both classes and structs (including SwiftUI views). The storage
/// is a reference type, so it can be mutated from non-mutating getters.
///
/// ## Usage
///
///     @Memoize
///     class Theme {
///         var colorScheme: ColorScheme = .dark
///
///         var progressStyle: LinearGradient {
///             #memoized(\Self.colorScheme) {
///                 LinearGradient(
///                     colors: colorScheme == .dark ? [.cyan, .green] : [.accentColor, .teal],
///                     startPoint: .topLeading,
///                     endPoint: .bottomTrailing
///                 )
///             }
///         }
///     }
///
@attached(member, names: named(_memoized))
public macro Memoize() = #externalMacro(module: "MemoizedMacros", type: "MemoizeMacro")

/// Memoizes a computed property, caching the result and only recomputing when
/// the specified dependency values change.
///
/// Use inside a computed property getter on a type annotated with `@Memoize`.
/// Pass one or more key paths identifying which properties the computation
/// depends on, followed by a trailing closure containing the computation.
///
/// ## Single Dependency
///
///     var style: String {
///         #memoized(\Self.colorScheme) {
///             colorScheme == .dark ? "dark-style" : "light-style"
///         }
///     }
///
/// ## Multiple Dependencies
///
///     var palette: String {
///         #memoized(\Self.colorScheme, \Self.fontSize) {
///             "\(colorScheme)-\(fontSize)"
///         }
///     }
///
/// The macro expands to a cache-check pattern that:
/// 1. Reads the current dependency values
/// 2. Returns the cached value if dependencies haven't changed
/// 3. Recomputes, caches, and returns the new value otherwise
///
/// > Important: The dependency key paths must point to `Equatable` values.
///   The enclosing type must be annotated with `@Memoize`.
///
@freestanding(expression)
public macro memoized<T>(_ deps: Any..., body: () -> T) -> T = #externalMacro(module: "MemoizedMacros", type: "MemoizedExprMacro")

// MARK: - Runtime Support

/// Shared memoization storage for a type. Holds per-property `MemoizedBox`
/// instances keyed by property name.
///
/// This is a reference type so it can be stored as a `let` on structs and
/// mutated from non-mutating getters (including SwiftUI `View.body`).
public final class MemoizedStorage: @unchecked Sendable {
    private var boxes: [String: Any] = [:]

    public init() {}

    /// Gets or creates a `MemoizedBox` for the given property key.
    public func box<Value>(for key: String, as type: Value.Type = Value.self) -> MemoizedBox<Value> {
        if let existing = boxes[key] as? MemoizedBox<Value> {
            return existing
        }
        let new = MemoizedBox<Value>()
        boxes[key] = new
        return new
    }
}

/// Reference-type memoization cache that can be mutated from a non-mutating
/// getter, making it safe for use in both classes and structs (including
/// SwiftUI views).
///
/// Uses type-erased equality checking via a closure so the concrete `Deps`
/// type only needs to be `Equatable`, not `Hashable`.
public final class MemoizedBox<Value>: @unchecked Sendable {
    private var cached: (value: Value, depsEqual: (Any) -> Bool)?

    public init() {}

    /// Returns the cached value if `currentDeps` match the stored snapshot,
    /// otherwise returns `nil`.
    public func value<Deps: Equatable>(for currentDeps: Deps) -> Value? {
        guard let cached, cached.depsEqual(currentDeps) else { return nil }
        return cached.value
    }

    /// Stores a new value alongside a snapshot of the dependencies that produced it.
    public func store<Deps: Equatable>(value: Value, deps: Deps) {
        self.cached = (value: value, depsEqual: { other in
            guard let otherDeps = other as? Deps else { return false }
            return otherDeps == deps
        })
    }
}

// MARK: - Multi-Dependency Wrappers

/// Equatable wrapper for 2 dependency values.
///
/// Used by the `#memoized` macro when multiple dependencies are specified.
/// Tuples cannot conform to `Equatable` in Swift, so this provides a
/// concrete type that can.
public struct Deps2<A: Equatable, B: Equatable>: Equatable {
    public let a: A
    public let b: B
    public init(_ a: A, _ b: B) { self.a = a; self.b = b }
}

/// Equatable wrapper for 3 dependency values.
public struct Deps3<A: Equatable, B: Equatable, C: Equatable>: Equatable {
    public let a: A
    public let b: B
    public let c: C
    public init(_ a: A, _ b: B, _ c: C) { self.a = a; self.b = b; self.c = c }
}

/// Equatable wrapper for 4 dependency values.
public struct Deps4<A: Equatable, B: Equatable, C: Equatable, D: Equatable>: Equatable {
    public let a: A
    public let b: B
    public let c: C
    public let d: D
    public init(_ a: A, _ b: B, _ c: C, _ d: D) { self.a = a; self.b = b; self.c = c; self.d = d }
}
