import Foundation

public enum LLMRefRenderer {
    private static let topLevelKinds: Set<String> = [
        "swift.class", "swift.struct", "swift.enum", "swift.protocol", "swift.typealias"
    ]

    private static let memberOrder: [String: Int] = [
        "swift.init": 0,
        "swift.type.property": 1,
        "swift.property": 2,
        "swift.enum.case": 3,
        "swift.type.method": 4,
        "swift.method": 5,
        "swift.subscript": 6,
        "swift.func.op": 7
    ]

    /// When this many or more contiguous undocumented enum cases appear in a
    /// single type, collapse them into one summary line.  Driven by the
    /// observation that doc-less case lists (e.g. enums modelling palettes,
    /// glyph sets, or icon catalogues) can dominate a module's reference and
    /// crowd out the symbols a reader is actually trying to find.  Cases with
    /// any doc-comment are never collapsed.
    private static let collapseEnumCaseThreshold = 10

    /// How many sample names to surface in the collapse-summary line.  Five
    /// is enough to convey naming style without becoming a list.
    private static let collapseEnumCaseSamples = 5

    /// Render a SymbolGraph as a flat, LLM-optimized markdown reference.
    public static func render(_ graph: SymbolGraph) -> String {
        let publicSymbols = graph.symbols.filter { $0.accessLevel == "public" }

        var buckets: [String: [SymbolGraph.Symbol]] = [:]
        for sym in publicSymbols {
            let parent = sym.pathComponents.dropLast().joined(separator: ".")
            buckets[parent, default: []].append(sym)
        }

        var out = ""
        out += "# \(graph.module.name) — LLM reference\n\n"
        out += "Auto-generated from symbol graph. Public surface only; signatures + doc-comments verbatim. "
        out += "Regenerate via the `generate-llm-ref` SPM command plugin.\n\n"
        out += "**Module:** \(graph.module.name)  •  **Symbols:** \(publicSymbols.count)\n\n"
        out += "---\n\n"

        let topLevel = (buckets[""] ?? []).sorted { a, b in
            let aTop = topLevelKinds.contains(a.kind.identifier) ? 0 : 1
            let bTop = topLevelKinds.contains(b.kind.identifier) ? 0 : 1
            if aTop != bTop { return aTop < bTop }
            return a.names.title.lowercased() < b.names.title.lowercased()
        }

        var emittedTypes: Set<String> = []
        for sym in topLevel {
            if topLevelKinds.contains(sym.kind.identifier) {
                emitType(sym, members: buckets[sym.names.title] ?? [], into: &out)
                emittedTypes.insert(sym.names.title)
            } else {
                emitMember(sym, into: &out)
                out += "\n"
            }
        }

        // Nested-type buckets (members whose parent type isn't itself a top-level
        // public symbol — e.g. extensions on a foreign type). Surface as untyped
        // sections so the symbols don't get dropped.
        let nested = buckets.keys
            .filter { !$0.isEmpty && !emittedTypes.contains($0) }
            .sorted()
        for parent in nested {
            out += "## \(parent)\n\n"
            let members = (buckets[parent] ?? []).sorted { memberKey($0) < memberKey($1) }
            for m in members { emitMember(m, into: &out) }
            out += "\n"
        }

        return out
    }

    // MARK: - Internals

    private static func renderSignature(_ symbol: SymbolGraph.Symbol) -> String {
        let raw = (symbol.declarationFragments ?? []).map(\.spelling).joined()
        return raw.replacingOccurrences(of: "\n", with: " ")
                  .replacingOccurrences(of: "  ", with: " ")
    }

    private static func renderDoc(_ doc: SymbolGraph.Symbol.DocComment?) -> String {
        guard let doc, !doc.lines.isEmpty else { return "" }
        var collapsed: [String] = []
        var prevBlank = false
        for line in doc.lines {
            let text = line.text.replacingOccurrences(of: "\u{00A0}", with: " ")
            let blank = text.trimmingCharacters(in: .whitespaces).isEmpty
            if blank, prevBlank { continue }
            collapsed.append(text)
            prevBlank = blank
        }
        while collapsed.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            collapsed.removeLast()
        }
        return collapsed.joined(separator: "\n")
    }

    private static func memberKey(_ s: SymbolGraph.Symbol) -> (Int, String) {
        (memberOrder[s.kind.identifier] ?? 99, s.names.title.lowercased())
    }

    private static func typeKindLabel(_ identifier: String) -> String {
        switch identifier {
        case "swift.class": return "class"
        case "swift.struct": return "struct"
        case "swift.enum": return "enum"
        case "swift.protocol": return "protocol"
        case "swift.typealias": return "typealias"
        default: return ""
        }
    }

    private static func emitType(
        _ sym: SymbolGraph.Symbol,
        members: [SymbolGraph.Symbol],
        into out: inout String
    ) {
        let label = typeKindLabel(sym.kind.identifier)
        out += "## \(sym.names.title)  _(\(label))_\n\n"
        out += "`\(renderSignature(sym))`\n\n"
        let doc = renderDoc(sym.docComment)
        if !doc.isEmpty {
            out += doc + "\n\n"
        }
        let sorted = members.sorted { memberKey($0) < memberKey($1) }
        emitMembersWithCaseCollapse(sorted, into: &out)
        if !sorted.isEmpty { out += "\n" }
    }

    /// Walk a presorted member list and emit each one, except that contiguous
    /// runs of undocumented enum cases ≥ `collapseEnumCaseThreshold` get
    /// collapsed into a single summary line.  The presorted input means cases
    /// already sit together (they share `memberOrder` rank), so a contiguous
    /// run is the natural unit to collapse.  Any case carrying a doc-comment
    /// is treated as non-collapsible and renders in full at its proper
    /// position, breaking the run if necessary.
    private static func emitMembersWithCaseCollapse(
        _ sorted: [SymbolGraph.Symbol],
        into out: inout String
    ) {
        var run: [SymbolGraph.Symbol] = []

        func flushRun() {
            guard !run.isEmpty else { return }
            if run.count >= collapseEnumCaseThreshold {
                emitCollapsedCases(run, into: &out)
            } else {
                for m in run { emitMember(m, into: &out) }
            }
            run.removeAll(keepingCapacity: true)
        }

        for m in sorted {
            if isCollapsibleEnumCase(m) {
                run.append(m)
            } else {
                flushRun()
                emitMember(m, into: &out)
            }
        }
        flushRun()
    }

    private static func isCollapsibleEnumCase(_ s: SymbolGraph.Symbol) -> Bool {
        guard s.kind.identifier == "swift.enum.case" else { return false }
        let doc = renderDoc(s.docComment)
        return doc.isEmpty
    }

    private static func emitCollapsedCases(
        _ cases: [SymbolGraph.Symbol],
        into out: inout String
    ) {
        let samples = cases.prefix(collapseEnumCaseSamples)
            .map { "`\($0.names.title)`" }
            .joined(separator: ", ")
        let ellipsis = cases.count > collapseEnumCaseSamples ? ", …" : ""
        out += "- _\(cases.count) undocumented enum cases (sample: \(samples)\(ellipsis))_\n"
    }

    private static func emitMember(_ sym: SymbolGraph.Symbol, into out: inout String) {
        out += "- `\(renderSignature(sym))`\n"
        let doc = renderDoc(sym.docComment)
        guard !doc.isEmpty else { return }
        for line in doc.split(separator: "\n", omittingEmptySubsequences: false) {
            out += "  \(line)\n"
        }
    }
}
