import Foundation
import LLMRefCore

let usage = "usage: llmref <symbols.json> [more.symbols.json ...] [-o output.md]\n"

// MARK: - Argument parsing

var inputs: [String] = []
var output: String? = nil

let argv = CommandLine.arguments
var i = 1
while i < argv.count {
    switch argv[i] {
    case "-o", "--output":
        i += 1
        guard i < argv.count else {
            FileHandle.standardError.write(Data("error: \(argv[i - 1]) requires a path\n".utf8))
            exit(64)
        }
        output = argv[i]
    case "-h", "--help":
        FileHandle.standardError.write(Data(usage.utf8))
        exit(0)
    default:
        inputs.append(argv[i])
    }
    i += 1
}

// Back-compat with the original `llmref <input.json> <output.md>` form: if no
// explicit -o was given and the trailing positional looks like a markdown path,
// treat it as the output.
if output == nil, inputs.count == 2, inputs[1].hasSuffix(".md") {
    output = inputs.removeLast()
}

guard !inputs.isEmpty else {
    FileHandle.standardError.write(Data(usage.utf8))
    exit(64)
}

// MARK: - Decode (one graph per input)

func decodeGraph(_ path: String) -> SymbolGraph {
    let url = URL(fileURLWithPath: path)
    let data: Data
    do {
        data = try Data(contentsOf: url)
    } catch {
        FileHandle.standardError.write(Data("error reading \(url.path): \(error)\n".utf8))
        exit(66)
    }
    do {
        return try JSONDecoder().decode(SymbolGraph.self, from: data)
    } catch {
        FileHandle.standardError.write(Data("error decoding symbol graph \(url.path): \(error)\n".utf8))
        exit(65)
    }
}

let graphs = inputs.map(decodeGraph)

// Merging several per-platform graphs yields a complete reference (e.g. UIKit
// iOS-only types alongside macOS-only ones). A single input is passed through
// unchanged.
let graph = graphs.count == 1 ? graphs[0] : SymbolGraph.merged(graphs)
let rendered = LLMRefRenderer.render(graph)
let publicCount = graph.symbols.filter { $0.accessLevel == "public" }.count

// MARK: - Output

if let output {
    let outURL = URL(fileURLWithPath: output)
    try? FileManager.default.createDirectory(
        at: outURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    do {
        try rendered.write(to: outURL, atomically: true, encoding: .utf8)
    } catch {
        FileHandle.standardError.write(Data("error writing \(outURL.path): \(error)\n".utf8))
        exit(73)
    }
    let from = inputs.count > 1 ? " (merged from \(inputs.count) graphs)" : ""
    FileHandle.standardError.write(Data("wrote \(publicCount) symbols\(from) → \(outURL.path)\n".utf8))
} else {
    print(rendered)
}
