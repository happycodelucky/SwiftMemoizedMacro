// MARK: - Macro Declaration

/// Memoizes a computed getter, caching the result and only recomputing
/// when the values at the specified dependency key paths change.
///
/// Apply to a computed property on a class or struct. Pass one or more
/// key paths identifying which properties the computation depends on.
///
/// ## Single Dependency
///
///     @Memoized(\.colorMode)
///     var resolvedPalette: Palette {
///         Palette.generate(mode: colorMode)
///     }
///
/// ## Multiple Dependencies
///
///     @Memoized(\.colorMode, \.accentHue)
///     var resolvedPalette: Palette {
///         Palette.generate(mode: colorMode, hue: accentHue)
///     }
///
/// The macro expands to:
/// - A private `MemoizedStorage` backing field (holds cached deps + value)
/// - A private `_compute_<name>()` function (the original getter body)
/// - A replacement getter that checks deps before recomputing
///
/// > Important: The dependency key paths must point to `Equatable` values.
///   The property must have an explicit type annotation.
///
@attached(accessor, names: named(get))
@attached(peer, names: prefixed(`_memoized_`), prefixed(`_compute_`))
public macro Memoized(_ deps: Any...) = #externalMacro(module: "MemoizedMacros", type: "MemoizedMacro")

// MARK: - Runtime Support

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
