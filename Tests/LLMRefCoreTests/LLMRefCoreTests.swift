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
}
