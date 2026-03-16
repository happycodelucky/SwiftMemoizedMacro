# Memoized

A Swift macro that turns computed properties into dependency-tracked cached getters. The cached value is only recomputed when the specified dependency properties change.

Think `useMemo` from React, but as a Swift macro.

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

1. **A backing storage field** (`_memoized_<name>`) — holds the cached deps snapshot + value
2. **A compute function** (`_compute_<name>()`) — the original getter body
3. **A replacement getter** — checks if deps changed before recomputing

```swift
// You write:
@Memoized(\.colorMode)
var palette: Palette {
    Palette.generate(mode: colorMode)
}

// Macro expands to:
private var _memoized_palette: MemoizedStorage<Palette>? = nil

private func _compute_palette() -> Palette {
    Palette.generate(mode: colorMode)
}

var palette: Palette {
    get {
        let deps = self.colorMode
        if let storage = _memoized_palette, storage.isValid(for: deps) {
            return storage.value
        }
        let value = _compute_palette()
        _memoized_palette = MemoizedStorage(deps: deps, value: value)
        return value
    }
}
```

## Requirements

- Swift 5.9+
- macOS 14+ / iOS 17+

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/happycodelucky/swift-memoized.git", from: "0.1.0"),
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: [
            .product(name: "Memoized", package: "swift-memoized"),
        ]
    ),
]
```

## Design Decisions

**Why key paths instead of automatic tracking?**
Explicit deps mean zero runtime overhead for observation tracking, no `withObservationTracking` complexity, and clear visibility into what triggers invalidation. It's the same philosophy as React's `useMemo` dependency array.

**Why type-erased storage?**
`MemoizedStorage<Value>` erases the `Deps` type via a closure so the macro doesn't need to spell out complex tuple types for the backing field. The `Deps` type only needs to be `Equatable`.

**Why not a property wrapper?**
Property wrappers can't access `self` at init time, so there's no way to read dependency key paths without external wiring. Macros can rewrite the getter to capture `self.<dep>` directly.
