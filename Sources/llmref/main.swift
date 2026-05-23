import Foundation
import LLMRefCore

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write(Data("usage: llmref <symbols.json> [output.md]\n".utf8))
    exit(64)
}

let inputURL = URL(fileURLWithPath: args[1])
let data: Data
do {
    data = try Data(contentsOf: inputURL)
} catch {
    FileHandle.standardError.write(Data("error reading \(inputURL.path): \(error)\n".utf8))
    exit(66)
}

let graph: SymbolGraph
do {
    graph = try JSONDecoder().decode(SymbolGraph.self, from: data)
} catch {
    FileHandle.standardError.write(Data("error decoding symbol graph: \(error)\n".utf8))
    exit(65)
}

let output = LLMRefRenderer.render(graph)

if args.count >= 3 {
    let outURL = URL(fileURLWithPath: args[2])
    try? FileManager.default.createDirectory(
        at: outURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    do {
        try output.write(to: outURL, atomically: true, encoding: .utf8)
    } catch {
        FileHandle.standardError.write(Data("error writing \(outURL.path): \(error)\n".utf8))
        exit(73)
    }
    let publicCount = graph.symbols.filter { $0.accessLevel == "public" }.count
    FileHandle.standardError.write(Data("wrote \(publicCount) symbols → \(outURL.path)\n".utf8))
} else {
    print(output)
}
