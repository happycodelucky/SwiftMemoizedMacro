import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

// MARK: - @Memoizable Member Macro

/// Generates shared memoization storage for a type.
///
/// Expands to:
///
///     private let _memoized = MemoizedStorage()
///
public struct MemoizableMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let storageDecl: DeclSyntax = """
            private let _memoized = MemoizedStorage()
            """

        return [storageDecl]
    }
}

// MARK: - #memoized Freestanding Expression Macro

/// Expands a `#memoized` call into a `MemoizedStorage.memoize()` invocation.
///
/// Input:
///
///     #memoized(\Self.colorScheme) {
///         LinearGradient(...)
///     }
///
/// Expands to:
///
///     _memoized.memoize(for: "colorScheme", deps: self.colorScheme) {
///         LinearGradient(...)
///     }
///
public struct MemoizedExprMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        // Extract arguments: key paths and trailing closure
        let arguments = node.arguments
        let trailingClosure = node.trailingClosure

        guard let closure = trailingClosure else {
            throw MacroError("#memoized requires a trailing closure containing the computation")
        }

        // Extract key paths from arguments (everything before the trailing closure)
        let keyPaths = try extractKeyPaths(from: arguments)
        guard !keyPaths.isEmpty else {
            throw MacroError("#memoized requires at least one dependency key path")
        }

        // Build the deps expression
        let depsExpr: String
        if keyPaths.count == 1 {
            depsExpr = "self.\(keyPaths[0])"
        } else {
            let joined = keyPaths.map { "self.\($0)" }.joined(separator: ", ")
            let depsWrapper = "Deps\(keyPaths.count)"
            depsExpr = "\(depsWrapper)(\(joined))"
        }

        // Build a stable storage key from the key paths
        let storageKey = keyPaths.joined(separator: ",")

        // Get the closure body
        let closureBody = closure.statements.trimmedDescription

        // Build the expansion that uses MemoizedStorage.memoize() which handles
        // the full cache-check + compute pattern and infers the Value type from the closure.
        let expansion: ExprSyntax = """
            _memoized.memoize(for: \(literal: storageKey), deps: \(raw: depsExpr)) {
                \(raw: closureBody)
            }
            """

        return expansion
    }

    // MARK: - Key Path Extraction

    private static func extractKeyPaths(from arguments: LabeledExprListSyntax?) throws -> [String] {
        guard let arguments else { return [] }

        var keyPaths: [String] = []

        for arg in arguments {
            let expr = arg.expression.trimmedDescription
            // Handle \Self. prefix for key path expressions
            if expr.hasPrefix("\\Self.") {
                keyPaths.append(String(expr.dropFirst(6)))
            } else if expr.hasPrefix("\\.") {
                keyPaths.append(String(expr.dropFirst(2)))
            } else {
                // Skip non-key-path arguments (e.g., the body label)
                continue
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
        MemoizableMacro.self,
        MemoizedExprMacro.self,
    ]
}
