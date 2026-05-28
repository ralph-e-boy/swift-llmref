import Foundation
import XCTest
@testable import LLMRefCore

final class LLMRefCoreTests: XCTestCase {
    func loadFixture(named name: String) throws -> SymbolGraph {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "json")
        )
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(SymbolGraph.self, from: data)
    }

    func testRendersTopLevelType() throws {
        let graph = try loadFixture(named: "tiny.symbols")
        let out = LLMRefRenderer.render(graph)

        XCTAssertTrue(out.contains("# Tiny — LLM reference"),
                      "header should name the module")
        XCTAssertTrue(out.contains("## Boxes  _(enum)_"),
                      "should render the enum heading")
        XCTAssertTrue(out.contains("A trivial container namespace."),
                      "should include type doc-comment")
    }

    func testEmitsPublicMembersWithSignaturesAndDocs() throws {
        let graph = try loadFixture(named: "tiny.symbols")
        let out = LLMRefRenderer.render(graph)

        XCTAssertTrue(out.contains("static func empty() -> Int"),
                      "should reconstruct the public method signature from declarationFragments")
        XCTAssertTrue(out.contains("Returns the empty box count."),
                      "should include the public method's doc-comment")
        XCTAssertTrue(out.contains("- Returns: Always zero."),
                      "should preserve structured doc-comment lines")
    }

    func testOmitsInternalSymbols() throws {
        let graph = try loadFixture(named: "tiny.symbols")
        let out = LLMRefRenderer.render(graph)

        XCTAssertFalse(out.contains("secret"),
                       "internal symbols must not appear in the public reference")
    }

    func testReportsSymbolCount() throws {
        let graph = try loadFixture(named: "tiny.symbols")
        let out = LLMRefRenderer.render(graph)

        // Two public symbols in the fixture (the enum + its static method).
        XCTAssertTrue(out.contains("Symbols:** 2"),
                      "header should report the public symbol count")
    }

    // MARK: - Enum-case collapse

    func testSmallEnumCaseRunRendersNormally() throws {
        let graph = try loadFixture(named: "cases.symbols")
        let out = LLMRefRenderer.render(graph)

        XCTAssertTrue(out.contains("case alpha"),
                      "below-threshold runs should render each case in full")
        XCTAssertTrue(out.contains("case beta"))
        XCTAssertTrue(out.contains("case gamma"))
        XCTAssertFalse(out.contains("3 undocumented enum cases"),
                       "3-case run should NOT trigger the collapse summary")
    }

    func testLargeUndocumentedEnumRunCollapses() throws {
        let graph = try loadFixture(named: "cases.symbols")
        let out = LLMRefRenderer.render(graph)

        // The 12-case Large enum should produce the collapse summary line
        // with the first 5 names sampled.
        XCTAssertTrue(out.contains("12 undocumented enum cases"),
                      "12-case run should collapse into the summary line")
        XCTAssertTrue(out.contains("`amber`, `blue`, `crimson`, `denim`, `ecru`"),
                      "summary should sample the first 5 case names")
        XCTAssertTrue(out.contains(", …"),
                      "summary should signal there are more cases beyond the sample")

        // Individual case bullets for Large should be suppressed.
        XCTAssertFalse(out.contains("- `case fawn`"),
                       "individual case bullets must not appear when the run is collapsed")
        XCTAssertFalse(out.contains("- `case lavender`"),
                       "individual case bullets must not appear when the run is collapsed")
    }

    func testDocumentedCaseBreaksTheRun() throws {
        let graph = try loadFixture(named: "cases.symbols")
        let out = LLMRefRenderer.render(graph)

        // Mixed has 12 cases — 11 undocumented, 1 (`jaguar`) documented in the
        // middle.  The documented case breaks the run into two sub-runs of 9
        // (a…i) and 2 (koala, lemur).  Neither sub-run hits the 10 threshold,
        // so EVERY case should render in full.
        XCTAssertTrue(out.contains("case aardvark"),
                      "broken run below threshold should render each case in full")
        XCTAssertTrue(out.contains("case ibis"))
        XCTAssertTrue(out.contains("case jaguar"),
                      "the documented case itself always renders in full")
        XCTAssertTrue(out.contains("The documented one — should not collapse."),
                      "documented case keeps its doc-comment")
        XCTAssertTrue(out.contains("case koala"),
                      "post-break run below threshold renders in full")
        XCTAssertTrue(out.contains("case lemur"))

        XCTAssertFalse(out.contains("undocumented enum cases (sample: `aardvark`"),
                       "9-case sub-run must not trigger the collapse")
        XCTAssertFalse(out.contains("undocumented enum cases (sample: `koala`"),
                       "2-case sub-run must not trigger the collapse")
    }

    // MARK: - Multi-platform merge

    /// Build a minimal top-level type symbol for merge tests.
    private func makeType(precise: String, title: String, kind: String) -> SymbolGraph.Symbol {
        SymbolGraph.Symbol(
            kind: .init(identifier: kind),
            identifier: .init(precise: precise),
            pathComponents: [title],
            names: .init(title: title),
            declarationFragments: [.init(spelling: "class \(title)")],
            docComment: nil,
            accessLevel: "public"
        )
    }

    func testMergeUnionsPlatformOnlySymbolsAndDedupesShared() {
        let shared  = makeType(precise: "s:shared", title: "Graphics",          kind: "swift.class")
        let iosOnly = makeType(precise: "s:ios",    title: "ProcessingKitView", kind: "swift.class")
        let macOnly = makeType(precise: "s:mac",    title: "NSImageLoader",     kind: "swift.struct")

        let iosGraph = SymbolGraph(module: .init(name: "M"), symbols: [shared, iosOnly])
        let macGraph = SymbolGraph(module: .init(name: "M"), symbols: [shared, macOnly])

        let merged = SymbolGraph.merged([iosGraph, macGraph])

        XCTAssertEqual(Set(merged.symbols.map(\.identifier.precise)),
                       ["s:shared", "s:ios", "s:mac"],
                       "merge should union platform-only symbols from every graph")
        XCTAssertEqual(merged.symbols.filter { $0.identifier.precise == "s:shared" }.count, 1,
                       "a symbol present in multiple graphs must appear once")
        XCTAssertEqual(merged.module.name, "M",
                       "merged module name comes from the first graph")
    }

    func testMergedGraphRendersTypesFromBothPlatforms() {
        let iosGraph = SymbolGraph(module: .init(name: "M"),
                                   symbols: [makeType(precise: "s:ios", title: "ProcessingKitView", kind: "swift.class")])
        let macGraph = SymbolGraph(module: .init(name: "M"),
                                   symbols: [makeType(precise: "s:mac", title: "NSImageLoader", kind: "swift.struct")])

        let out = LLMRefRenderer.render(SymbolGraph.merged([iosGraph, macGraph]))

        XCTAssertTrue(out.contains("## ProcessingKitView"), "iOS-only type should render")
        XCTAssertTrue(out.contains("## NSImageLoader"), "macOS-only type should render")
        XCTAssertTrue(out.contains("Symbols:** 2"), "merged count reflects the union")
    }

    func testMergeEmptyInputYieldsEmptyGraph() {
        let merged = SymbolGraph.merged([])
        XCTAssertTrue(merged.symbols.isEmpty)
        XCTAssertEqual(merged.module.name, "")
    }
}
