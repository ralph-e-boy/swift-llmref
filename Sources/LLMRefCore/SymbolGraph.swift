import Foundation

/// Minimal partial schema for a Swift symbol-graph JSON file.
/// Captures only the fields the renderer consumes.
public struct SymbolGraph: Decodable, Sendable {
    public let module: Module
    public let symbols: [Symbol]

    public struct Module: Decodable, Sendable {
        public let name: String
    }

    public struct Symbol: Decodable, Sendable {
        public let kind: Kind
        public let identifier: Identifier
        public let pathComponents: [String]
        public let names: Names
        public let declarationFragments: [Fragment]?
        public let docComment: DocComment?
        public let accessLevel: String

        public struct Kind: Decodable, Sendable {
            public let identifier: String
        }

        public struct Identifier: Decodable, Sendable {
            public let precise: String
        }

        public struct Names: Decodable, Sendable {
            public let title: String
        }

        public struct Fragment: Decodable, Sendable {
            public let spelling: String
        }

        public struct DocComment: Decodable, Sendable {
            public let lines: [Line]
            public struct Line: Decodable, Sendable {
                public let text: String
            }
        }
    }
}

public extension SymbolGraph {
    /// Merge several symbol graphs of the *same module* — e.g. per-platform
    /// builds (`macOS` + `iOS` + `tvOS`) — into one. Symbols are unioned by
    /// `identifier.precise`; when the same symbol appears in more than one
    /// graph the **first occurrence wins**, so pass the most canonical graph
    /// first (the platform whose signatures you'd rather show — e.g. the iOS
    /// build, so `@MainActor`/UIKit-gated declarations are preserved). The
    /// merged module name is taken from the first graph.
    ///
    /// This is how a multiplatform package gets a *complete* reference:
    /// `#if canImport(UIKit)` types (iOS-only) and `#if os(macOS)` types
    /// (macOS-only) both survive, instead of whichever single build the
    /// extractor happened to run.
    static func merged(_ graphs: [SymbolGraph]) -> SymbolGraph {
        guard let first = graphs.first else {
            return SymbolGraph(module: Module(name: ""), symbols: [])
        }
        var seen = Set<String>()
        var symbols: [Symbol] = []
        for graph in graphs {
            for symbol in graph.symbols where seen.insert(symbol.identifier.precise).inserted {
                symbols.append(symbol)
            }
        }
        return SymbolGraph(module: first.module, symbols: symbols)
    }
}
