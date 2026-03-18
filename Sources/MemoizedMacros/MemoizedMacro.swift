import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

// MARK: - @Memoized Attached Macro

/// Transforms a stored property into a memoized computed property that caches
/// its result and only recomputes when the specified dependency key path values change.
///
/// Usage:
///
///     @Observable
///     class Theme {
///         var colorMode: ColorMode = .dark
///         var accentHue: Double = 210
///
///         @Memoized(\.colorMode)
///         var resolvedPalette: Palette = Palette.generate(mode: colorMode, hue: accentHue)
///     }
///
/// For multi-line computations, use a closure:
///
///     @Memoized(\.colorMode, \.accentHue)
///     var resolvedPalette: Palette = {
///         Palette.generate(mode: colorMode, hue: accentHue)
///     }()
///
/// Expands roughly to:
///
///     private let _memoized_resolvedPalette = MemoizedBox<Palette>()
///     var resolvedPalette: Palette {
///         get {
///             let deps = self.colorMode
///             if let cached = _memoized_resolvedPalette.value(for: deps) {
///                 return cached
///             }
///             let value = Palette.generate(mode: colorMode, hue: accentHue)
///             _memoized_resolvedPalette.store(value: value, deps: deps)
///             return value
///         }
///     }
///
public struct MemoizedMacro: AccessorMacro, PeerMacro {

    // MARK: - AccessorMacro (provides the memoized getter)

    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        guard let varDecl = declaration.as(VariableDeclSyntax.self),
              let binding = varDecl.bindings.first,
              let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
              binding.typeAnnotation != nil
        else {
            throw MacroError("@Memoized can only be applied to a property with an explicit type annotation")
        }

        let propName = identifier.identifier.text
        let keyPaths = try extractKeyPaths(from: node)
        guard !keyPaths.isEmpty else {
            throw MacroError("@Memoized requires at least one dependency key path")
        }

        // Require a stored property with initializer (not a computed property)
        guard binding.initializer != nil else {
            throw MacroError("@Memoized requires a stored property with an initializer expression")
        }

        let computeExpr = try extractComputeExpression(from: binding)
        let storageName = "_memoized_\(propName)"

        let depsExpr: String
        if keyPaths.count == 1 {
            depsExpr = "self.\(keyPaths[0])"
        } else {
            let joined = keyPaths.map { "self.\($0)" }.joined(separator: ", ")
            depsExpr = "(\(joined))"
        }

        let accessor: AccessorDeclSyntax = """
            get {
                let deps = \(raw: depsExpr)
                if let cached = \(raw: storageName).value(for: deps) {
                    return cached
                }
                let value = \(raw: computeExpr)
                \(raw: storageName).store(value: value, deps: deps)
                return value
            }
            """

        return [accessor]
    }

    // MARK: - PeerMacro (generates backing storage)

    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let varDecl = declaration.as(VariableDeclSyntax.self),
              let binding = varDecl.bindings.first,
              let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
              let typeAnnotation = binding.typeAnnotation
        else {
            return []
        }

        let propName = identifier.identifier.text
        let valueType = typeAnnotation.type.trimmedDescription
        let keyPaths = try extractKeyPaths(from: node)

        guard !keyPaths.isEmpty else { return [] }

        // Only generate peers for stored properties with initializers
        guard binding.initializer != nil else { return [] }

        let storageName = "_memoized_\(propName)"

        // Generate: private let _memoized_X = MemoizedBox<ValueType>()
        let storageDecl: DeclSyntax = """
            private let \(raw: storageName) = MemoizedBox<\(raw: valueType)>()
            """

        return [storageDecl]
    }

    // MARK: - Compute Expression Extraction

    /// Extracts the computation expression from the property's initializer.
    ///
    /// Supports:
    /// - Simple initializer: `var x: T = expression`
    /// - Closure initializer: `var x: T = { ... }()`
    private static func extractComputeExpression(from binding: PatternBindingSyntax) throws -> String {
        guard let initializer = binding.initializer else {
            throw MacroError("@Memoized requires a stored property with an initializer expression")
        }

        // Handle closure initializer: `{ ... }()`
        // Strip the trailing `()` and the outer braces to get the body
        if let closureExpr = initializer.value.as(FunctionCallExprSyntax.self),
           let closure = closureExpr.calledExpression.as(ClosureExprSyntax.self) {
            return closure.statements.trimmedDescription
        }

        return initializer.value.trimmedDescription
    }

    // MARK: - Key Path Extraction

    private static func extractKeyPaths(from node: AttributeSyntax) throws -> [String] {
        guard let arguments = node.arguments?.as(LabeledExprListSyntax.self) else {
            return []
        }

        var keyPaths: [String] = []

        for arg in arguments {
            let expr = arg.expression.trimmedDescription
            // Handle \. prefix for key path expressions
            if expr.hasPrefix("\\.") {
                keyPaths.append(String(expr.dropFirst(2)))
            } else if expr.hasPrefix("\\Self.") {
                keyPaths.append(String(expr.dropFirst(6)))
            } else {
                // Assume it's a bare property name
                keyPaths.append(expr)
            }
        }

        return keyPaths
    }
}

// MARK: - Error Type

struct MacroError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) {
        self.description = description
    }
}

// MARK: - Plugin Entry Point

@main
struct MemoizedPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        MemoizedMacro.self,
    ]
}
