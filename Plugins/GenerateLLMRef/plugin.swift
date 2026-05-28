import Foundation
import PackagePlugin

@main
struct GenerateLLMRef: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        var extractor = ArgumentExtractor(arguments)
        let requested = extractor.extractOption(named: "target")
        let outputOverride = extractor.extractOption(named: "output").first

        let candidates: [SourceModuleTarget] = context.package.targets
            .compactMap { $0 as? SourceModuleTarget }
            .filter { $0.kind == .generic }

        let targets: [SourceModuleTarget]
        if requested.isEmpty {
            targets = candidates
        } else {
            let nameSet = Set(requested)
            targets = candidates.filter { nameSet.contains($0.name) }
            let missing = nameSet.subtracting(targets.map(\.name))
            if !missing.isEmpty {
                Diagnostics.error("target(s) not found: \(missing.sorted().joined(separator: ", "))")
                return
            }
        }

        guard !targets.isEmpty else {
            Diagnostics.error("no source-module targets to process")
            return
        }

        if outputOverride != nil, targets.count > 1 {
            Diagnostics.error("--output can only be combined with a single --target")
            return
        }

        let tool = try context.tool(named: "llmref")
        let packageDir = context.package.directory

        for target in targets {
            print("Generating LLM ref for \(target.name)…")

            let result = try packageManager.getSymbolGraph(
                for: target,
                options: .init(
                    minimumAccessLevel: .public,
                    includeSynthesized: false,
                    includeSPI: false
                )
            )

            let symbolsPath = result.directoryPath.appending(subpath: "\(target.name).symbols.json")
            guard FileManager.default.fileExists(atPath: symbolsPath.string) else {
                Diagnostics.error("symbol graph not found at \(symbolsPath.string)")
                continue
            }

            let outputPath: Path = outputOverride.map { Path($0) }
                ?? packageDir.appending(subpath: "docs/\(target.name).llm.md")

            let outputDir = Path(outputPath.string).removingLastComponent()
            try? FileManager.default.createDirectory(
                atPath: outputDir.string,
                withIntermediateDirectories: true
            )

            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool.path.string)
            process.arguments = [symbolsPath.string, "-o", outputPath.string]
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                Diagnostics.error("llmref failed for \(target.name) (exit \(process.terminationStatus))")
                continue
            }
            print("  → \(outputPath.string)")
        }
    }
}
