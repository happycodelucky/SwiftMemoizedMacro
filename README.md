# Memoized

![Swift 6.0+](https://img.shields.io/badge/Swift-6.0%2B-F05138.svg?style=for-the-badge&logo=swift&logoColor=white)
![macOS 14+ | iOS 17+](https://img.shields.io/badge/macOS%2014%2B%20%7C%20iOS%2017%2B-blue.svg?style=for-the-badge&logo=apple)
[![Release](https://img.shields.io/github/v/release/happycodelucky/SwiftMemoizedMacro?style=for-the-badge)](https://github.com/happycodelucky/SwiftMemoizedMacro/releases/latest)
<br/>
[![CI](https://img.shields.io/github/actions/workflow/status/happycodelucky/SwiftMemoizedMacro/tests.yml?style=for-the-badge&label=ci)](https://github.com/happycodelucky/SwiftMemoizedMacro/actions/workflows/tests.yml)
[![Maintained](https://img.shields.io/badge/Maintained%3F-yes-green.svg?style=for-the-badge)](https://github.com/happycodelucky/SwiftMemoizedMacro/graphs/commit-activity)

A Swift macro that turns computed properties into dependency-tracked cached getters. The cached value is only recomputed when the specified dependency properties change.

Think `useMemo` from React, but as a Swift macro.

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/happycodelucky/SwiftMemoizedMacro.git", from: "0.3.0"),
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: [
            .product(name: "Memoized", package: "SwiftMemoizedMacro"),
        ]
    ),
]
```

## Usage

Add `@Memoize` to your type and use `#memoized` inside computed property getters.

### Single Dependency

```swift
import Memoized

@Memoize
@Observable
class Theme {
    var colorMode: ColorMode = .dark

    // Only recomputes when colorMode changes
    var resolvedPalette: Palette {
        #memoized(\Self.colorMode) {
            Palette.generate(mode: colorMode)
        }
    }
}
```

### Multiple Dependencies

```swift
@Memoize
@Observable
class Theme {
    var colorMode: ColorMode = .dark
    var accentHue: Double = 210
    var fontSize: CGFloat = 14

    // Recomputes when colorMode OR accentHue changes
    // Does NOT recompute when fontSize changes
    var resolvedPalette: Palette {
        #memoized(\Self.colorMode, \Self.accentHue) {
            Palette.generate(mode: colorMode, hue: accentHue)
        }
    }
}
```

### Multi-line Computation

```swift
@Memoize
@Observable
class Theme {
    var colorMode: ColorMode = .dark
    var accentHue: Double = 210

    var resolvedPalette: Palette {
        #memoized(\Self.colorMode, \Self.accentHue) {
            let mode = colorMode
            let hue = accentHue
            return Palette.generate(mode: mode, hue: hue)
        }
    }
}
```

### In SwiftUI Views

```swift
@Memoize
struct ContentView: View {
    @Environment(\.colorScheme) var colorScheme

    var progressStyle: LinearGradient {
        #memoized(\Self.colorScheme) {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color.cyan, Color.green]
                    : [Color.accentColor, Color.teal],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    var body: some View {
        ProgressView(value: 0.7)
            .progressViewStyle(.linear)
            .tint(progressStyle)
    }
}
```

### Structs

```swift
@Memoize
struct Settings {
    var threshold: Int = 10

    var label: String {
        #memoized(\Self.threshold) {
            "Threshold: \(threshold)"
        }
    }
}
```

## How It Works

The library uses two macros that work together:

### `@Memoize` (type-level)

Applied to a class or struct, generates shared memoization storage:

```swift
// Generates:
private let _memoized = MemoizedStorage()
```

`MemoizedStorage` is a reference type that holds per-property `MemoizedBox` caches keyed by property name.

### `#memoized` (expression-level)

Used inside a computed property getter, expands to a cache-check pattern:

```swift
// You write:
var palette: Palette {
    #memoized(\Self.colorMode) {
        Palette.generate(mode: colorMode)
    }
}

// Macro expands to:
var palette: Palette {
    {
        let _box: MemoizedBox = _memoized.box(for: "palette")
        let _deps = self.colorMode
        if let _cached = _box.value(for: _deps) {
            return _cached
        }
        let _value = {
            Palette.generate(mode: colorMode)
        }()
        _box.store(value: _value, deps: _deps)
        return _value
    }()
}
```

The property name is automatically extracted from the enclosing lexical context — you don't need to specify it.

For multiple dependencies, the macro wraps them in an `Equatable` struct (`Deps2`, `Deps3`, `Deps4`) since Swift tuples cannot conform to protocols.

## Struct Copy Behavior

`MemoizedStorage` is a reference type (`class`), which means struct copies share the same cache. This is important to understand:

```swift
var a = Settings(threshold: 10)
var b = a                        // shares the same MemoizedStorage

print(a.label)                   // computes and caches for threshold=10
print(b.label)                   // cache hit ✅ (same deps)

a.threshold = 20
print(a.label)                   // cache miss, recomputes for threshold=20
print(b.label)                   // cache miss, recomputes for threshold=10
print(a.label)                   // cache miss again (b overwrote the cache)
```

**This is always safe** — the dependency check guarantees you never get a stale or incorrect value. However, if two struct copies are independently mutated, they will cause cache thrashing (frequent recomputation) because they alternate overwriting each other's cached values.

**In practice this rarely matters:**
- **Classes** have a single reference, so no copies exist
- **SwiftUI views** are short-lived value types that aren't independently mutated after creation
- **Immutable struct copies** share the cache beneficially (same deps = cache hits)

Cache thrashing only occurs when mutable struct copies are independently mutated and both actively access memoized properties — an uncommon pattern for the intended use cases.

## Design Decisions

**Why two macros (`@Memoize` + `#memoized`) instead of one?**
Swift's macro system validates all source code before macro expansion. An `@attached(accessor)` macro on a stored property can't reference `self` in the initializer (the compiler rejects it before the macro runs). By using a freestanding `#memoized` expression macro inside a computed property getter — where `self` is already available — the compiler is happy and the macro can freely reference instance properties.

**Why key paths instead of automatic tracking?**
Explicit deps mean zero runtime overhead for observation tracking, no `withObservationTracking` complexity, and clear visibility into what triggers invalidation. It's the same philosophy as React's `useMemo` dependency array.

**Why a reference-type storage?**
`MemoizedStorage` and `MemoizedBox` are classes so the getter can update the cache without mutating `self`, making it work in both classes and structs (including SwiftUI views where `body` is a non-mutating getter).

**Why not a property wrapper?**
Swift's `@propertyWrapper` has no access to `self` of the enclosing type — `wrappedValue` can't read sibling properties. The `_enclosingInstance` static subscript is class-only and uses non-public API, ruling out structs and SwiftUI views.

**Why `Deps2`/`Deps3`/`Deps4` instead of tuples?**
Swift tuples cannot conform to `Equatable` (or any protocol). The `Deps` wrapper types provide the same structure with `Equatable` conformance, supporting up to 4 dependencies.
