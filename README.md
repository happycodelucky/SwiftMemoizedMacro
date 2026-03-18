# Memoized

![Swift 6.0+](https://img.shields.io/badge/Swift-6.0%2B-F05138.svg?style=for-the-badge&logo=swift&logoColor=white)
![macOS 14+ | iOS 17+](https://img.shields.io/badge/macOS%2014%2B%20%7C%20iOS%2017%2B-blue.svg?style=for-the-badge&logo=apple)
[![Release](https://img.shields.io/github/v/release/happycodelucky/SwiftMemoizedMacro?style=for-the-badge)](https://github.com/happycodelucky/SwiftMemoizedMacro/releases/latest)
<br/>
[![CI](https://img.shields.io/github/actions/workflow/status/happycodelucky/SwiftMemoizedMacro/tests.yml?style=for-the-badge&label=ci)](https://github.com/happycodelucky/SwiftMemoizedMacro/actions/workflows/tests.yml)
[![Maintained](https://img.shields.io/badge/Maintained%3F-yes-green.svg?style=for-the-badge)](https://github.com/happycodelucky/SwiftMemoizedMacro/graphs/commit-activity)

A Swift macro that turns stored properties into dependency-tracked cached getters. The cached value is only recomputed when the specified dependency properties change.

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

### Single Dependency

```swift
import Memoized

@Observable
class Theme {
    var colorMode: ColorMode = .dark

    // Only called once per colorMode value
    @Memoized(\.colorMode)
    var resolvedPalette: Palette = Palette.generate(mode: colorMode)
}
```

### Multiple Dependencies

```swift
@Observable
class Theme {
    var colorMode: ColorMode = .dark
    var accentHue: Double = 210
    var fontSize: CGFloat = 14

    // Recomputes when colorMode OR accentHue changes
    // Does NOT recompute when fontSize changes
    @Memoized(\.colorMode, \.accentHue)
    var resolvedPalette: Palette = Palette.generate(mode: colorMode, hue: accentHue)
}
```

### Multi-line Computation (closure syntax)

```swift
@Observable
class Theme {
    var colorMode: ColorMode = .dark
    var accentHue: Double = 210

    @Memoized(\.colorMode, \.accentHue)
    var resolvedPalette: Palette = {
        let mode = colorMode
        let hue = accentHue
        return Palette.generate(mode: mode, hue: hue)
    }()
}
```

### In SwiftUI Views

```swift
struct ContentView: View {
    @State private var theme = Theme()

    var body: some View {
        // theme.resolvedPalette is cached — accessing it multiple times
        // in the same render pass costs nothing after the first call.
        VStack {
            Text("Hello")
                .foregroundStyle(theme.resolvedPalette.primary)
            Text("World")
                .foregroundStyle(theme.resolvedPalette.secondary)
        }
    }
}
```

## How It Works

The `@Memoized` macro expands a stored property into:

1. **A backing storage box** (`_memoized_<name>`) — a reference-type cache holding the deps snapshot + value
2. **A computed getter** — checks if deps changed before recomputing using the initializer expression

```swift
// You write:
@Memoized(\.colorMode)
var palette: Palette = Palette.generate(mode: colorMode)

// Macro expands to:
private let _memoized_palette = MemoizedBox<Palette>()

var palette: Palette {
    get {
        let deps = self.colorMode
        if let cached = _memoized_palette.value(for: deps) {
            return cached
        }
        let value = Palette.generate(mode: colorMode)
        _memoized_palette.store(value: value, deps: deps)
        return value
    }
}
```

## Design Decisions

**Why key paths instead of automatic tracking?**
Explicit deps mean zero runtime overhead for observation tracking, no `withObservationTracking` complexity, and clear visibility into what triggers invalidation. It's the same philosophy as React's `useMemo` dependency array.

**Why a reference-type box?**
`MemoizedBox<Value>` is a class so the getter can update the cache without mutating `self`, making it work in both classes and structs (including SwiftUI views). It erases the `Deps` type via a closure so the macro doesn't need to spell out complex tuple types. The `Deps` type only needs to be `Equatable`.

**Why stored properties, not computed properties?**
Swift's `@attached(accessor)` macro can only *add* accessors to a declaration — it cannot remove or replace existing ones. Applying it to a computed property that already has a getter body results in two conflicting `get` blocks. On a stored property, the macro's accessor cleanly replaces the storage, converting it into a computed property. This is the same pattern `@Observable` uses.

**Why not a property wrapper?**
Swift's `@propertyWrapper` has no access to `self` of the enclosing type — `wrappedValue` can't read sibling properties. The `_enclosingInstance` static subscript is class-only and uses non-public API, ruling out structs and SwiftUI views. A macro can rewrite the getter to capture `self.<dep>` directly, making it strictly more powerful for this use case.
