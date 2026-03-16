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
    .package(url: "https://github.com/happycodelucky/SwiftMemoizedMacro.git", from: "0.2.0"),
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

    @Memoized(\.colorMode)
    var resolvedPalette: Palette {
        // Only called once per colorMode value
        Palette.generate(mode: colorMode)
    }
}
```

### Multiple Dependencies

```swift
@Observable
class Theme {
    var colorMode: ColorMode = .dark
    var accentHue: Double = 210
    var fontSize: CGFloat = 14

    @Memoized(\.colorMode, \.accentHue)
    var resolvedPalette: Palette {
        // Recomputes when colorMode OR accentHue changes
        // Does NOT recompute when fontSize changes
        Palette.generate(mode: colorMode, hue: accentHue)
    }
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

The `@Memoized` macro expands a computed property into:

1. **A backing storage box** (`_memoized_<name>`) — a reference-type cache holding the deps snapshot + value
2. **A compute function** (`_compute_<name>()`) — the original getter body
3. **A replacement getter** — checks if deps changed before recomputing

```swift
// You write:
@Memoized(\.colorMode)
var palette: Palette {
    Palette.generate(mode: colorMode)
}

// Macro expands to:
private let _memoized_palette = MemoizedBox<Palette>()

private func _compute_palette() -> Palette {
    Palette.generate(mode: colorMode)
}

var palette: Palette {
    get {
        let deps = self.colorMode
        if let cached = _memoized_palette.value(for: deps) {
            return cached
        }
        let value = _compute_palette()
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

**Why not a property wrapper?**
Property wrappers can't access `self` at init time, so there's no way to read dependency key paths without external wiring. Macros can rewrite the getter to capture `self.<dep>` directly.
