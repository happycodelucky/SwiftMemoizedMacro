import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

// MARK: - @Memoized Attached Macro

/// Transforms a computed getter into a memoized getter that caches its result
/// and only recomputes when the specified dependency key path values change.
///
/// Usage:
///
///     @Observable
///     class Theme {
///         var colorMode: ColorMode = .dark
///         var accentHue: Double = 210
///
///         @Memoized(\.colorMode)
///         var resolvedPalette: Palette {
///             Palette.generate(mode: colorMode, hue: accentHue)
///         }
///     }
///
/// Expands roughly to:
///
///     private let _memoized_resolvedPalette = MemoizedBox<Palette>()
///     var resolvedPalette: Palette {
///         let deps = self.colorMode
///         if let cached = _memoized_resolvedPalette.value(for: deps) {
///             return cached
///         }
///         let value = _compute_resolvedPalette()
///         _memoized_resolvedPalette.store(value: value, deps: deps)
///         return value
///     }
///     private func _compute_resolvedPalette() -> Palette {
///         Palette.generate(mode: colorMode, hue: accentHue)
///     }
///
public struct MemoizedMacro: AccessorMacro, PeerMacro {

    // MARK: - AccessorMacro (replaces the getter)

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
            throw MacroError("@Memoized can only be applied to a computed property with an explicit type annotation")
        }

        let propName = identifier.identifier.text
        let keyPaths = try extractKeyPaths(from: node)

        guard !keyPaths.isEmpty else {
            throw MacroError("@Memoized requires at least one dependency key path")
        }

        let storageName = "_memoized_\(propName)"
        let computeFnName = "_compute_\(propName)"

        let depsExpr: String
        if keyPaths.count == 1 {
            depsExpr = "self.\(keyPaths[0])"
        } else {
            let joined = keyPaths.map { "self.\($0)" }.joined(separator: ", ")
            depsExpr = "(\(joined))"
        }

        let accessor: AccessorDeclSyntax = """
            let deps = \(raw: depsExpr)
            if let cached = \(raw: storageName).value(for: deps) {
                return cached
            }
            let value = \(raw: computeFnName)()
            \(raw: storageName).store(value: value, deps: deps)
            return value
            """

        return [accessor]
    }

    // MARK: - PeerMacro (generates backing storage + compute function)

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

        // Extract the original getter body
        let getterBody: String
        if let accessorBlock = binding.accessorBlock {
            if let accessors = accessorBlock.accessors.as(AccessorDeclListSyntax.self) {
                // Explicit `get { ... }`
                if let getter = accessors.first(where: { $0.accessorSpecifier.text == "get" }),
                   let body = getter.body {
                    getterBody = body.statements.trimmedDescription
                } else {
                    throw MacroError("@Memoized requires a getter")
                }
            } else if let codeBlock = accessorBlock.accessors.as(CodeBlockItemListSyntax.self) {
                // Implicit getter: `var x: T { ... }`
                getterBody = codeBlock.trimmedDescription
            } else {
                throw MacroError("@Memoized requires a computed property with a getter body")
            }
        } else {
            throw MacroError("@Memoized requires a computed property, not a stored property")
        }

        let storageName = "_memoized_\(propName)"
        let computeFnName = "_compute_\(propName)"

        // Generate: private let _memoized_X = MemoizedBox<ValueType>()
        // A reference type so the getter can mutate it without mutating self.
        let storageDecl: DeclSyntax = """
            private let \(raw: storageName) = MemoizedBox<\(raw: valueType)>()
            """

        // Generate: private func _compute_X() -> ValueType { <original body> }
        let computeDecl: DeclSyntax = """
            private func \(raw: computeFnName)() -> \(raw: valueType) {
                \(raw: getterBody)
            }
            """

        return [storageDecl, computeDecl]
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
