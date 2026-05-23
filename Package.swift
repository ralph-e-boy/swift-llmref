// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "swift-llmref",
    platforms: [.macOS(.v13)],
    products: [
        .plugin(name: "GenerateLLMRef", targets: ["GenerateLLMRef"]),
        .executable(name: "llmref", targets: ["llmref"]),
        .library(name: "LLMRefCore", targets: ["LLMRefCore"])
    ],
    targets: [
        .target(name: "LLMRefCore"),
        .executableTarget(
            name: "llmref",
            dependencies: ["LLMRefCore"]
        ),
        .plugin(
            name: "GenerateLLMRef",
            capability: .command(
                intent: .custom(
                    verb: "generate-llm-ref",
                    description: "Generate compact LLM-optimized API reference from Swift symbol graphs."
                ),
                permissions: [
                    .writeToPackageDirectory(
                        reason: "writes <Module>.llm.md into the package's docs/ directory"
                    )
                ]
            ),
            dependencies: [.target(name: "llmref")]
        ),
        .testTarget(
            name: "LLMRefCoreTests",
            dependencies: ["LLMRefCore"],
            resources: [.copy("Fixtures")]
        )
    ]
)
