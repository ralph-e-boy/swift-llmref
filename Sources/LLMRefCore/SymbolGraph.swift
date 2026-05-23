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
