# swift-llmref

**An SPM command plugin that generates compact, LLM-optimized API references for Swift packages.**

When you point an LLM at a Swift package and ask it to integrate the library, it has to learn the API somehow. The usual options all have problems:

| Source | What you get | Cost to an LLM |
|---|---|---|
| Read the source | Everything (incl. private helpers, bodies, comments about strategy) | High — you pay for noise |
| `.swiftinterface` | Signatures only | Low — but **doc-comments are stripped**; the *why* is gone |
| DocC archive | Signatures + docs + articles | Medium-high — many files, JSON-with-presentational-metadata, navigation tax |
| **`.llm.md` (this plugin)** | **Public surface only, signatures + doc-comments inline, flat markdown** | **Low — single file, greppable, ~4× smaller than source** |

The Swift compiler emits the symbol graph as JSON (via `-emit-symbol-graph`) — the same data DocC consumes — but for an LLM the JSON's shape is heavier than necessary. swift-llmref reads that JSON and writes a flat Markdown reference: one bullet per public symbol, signature in a code-fence, the original doc-comment immediately below. No HTML, no presentational metadata, no per-symbol files to navigate.

For a representative package (~170 public symbols), the output is roughly **~4× smaller than full source** and **~2× larger than the bare `.swiftinterface`** — the difference being the preserved doc-comments.

---

## Install

Add the package to your `Package.swift` dependencies:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "YourPackage",
    dependencies: [
        .package(url: "https://github.com/ralph-e-boy/swift-llmref", from: "0.0.1")
    ],
    targets: [
        .target(name: "YourPackage")
    ]
)
```

That's it. The plugin is invoked via `swift package`, so no target dependency is needed — it lives outside your target graph and never gets linked into your binary.

**Requirements:**
- Swift 5.9+ (uses the legacy `PackagePlugin.Path` API for compatibility)
- macOS 13+ (for symbol-graph emission)

---

## Use

From your package root:

```bash
swift package --allow-writing-to-package-directory generate-llm-ref
```

By default, this emits one `docs/<TargetName>.llm.md` per source-module target (skipping tests, executables, and snippets).

### Options

| Flag | Effect |
|---|---|
| `--target <name>` | Generate ref for a specific target. Repeatable. Defaults to all source-module targets. |
| `--output <path>` | Write to a custom path. Only valid when combined with a single `--target`. |

### Examples

```bash
# All targets → docs/<TargetName>.llm.md each
swift package --allow-writing-to-package-directory generate-llm-ref

# One target, default output (docs/MyLibrary.llm.md)
swift package --allow-writing-to-package-directory generate-llm-ref --target MyLibrary

# One target, custom output
swift package --allow-writing-to-package-directory generate-llm-ref \
    --target MyLibrary --output docs/api.md

# Multiple targets
swift package --allow-writing-to-package-directory generate-llm-ref \
    --target MyLibrary --target MyHelpers
```

Commit the generated `docs/*.llm.md` files. Regenerate them whenever the public API changes — the same way you'd regenerate any other documentation artifact.

---

## What the output looks like

```markdown
## PeakDetection  _(enum)_

`enum PeakDetection`

Stateless frequency-domain peak detection utilities.

- `static func fundamentalFrequency(magnitudes: [Float], sampleRate: Double, fftSize: Int, minFreq: Double, maxFreq: Double, magnitudeThreshold: Float = 0.12) -> (index: Int, rawFrequency: Double)?`
  Finds the fundamental frequency bin using harmonic scoring.

  Scores each candidate bin by its magnitude plus 50% credit for harmonics 2–5.
  Low-frequency candidates (< 300 Hz) receive a 20% boost.

  - Parameters:
    - magnitudes: Squared-magnitude spectrum (from `Spectrum.magnitudes`).
    - magnitudeThreshold: Bins below this power are skipped. Default 0.12 (for squared magnitudes).
```

One symbol per bullet, full signature in the code-fence, doc-comment indented underneath. Parameter docs and return-value docs preserved verbatim. Grep, paste, or `Read`-tool the whole file in one go.

---

## How it works

1. The command plugin calls `PackageManager.getSymbolGraph(for: target, options: .init(minimumAccessLevel: .public, includeSynthesized: false))` — same API DocC uses to walk a package.
2. The result is a JSON file at `<plugin-work-dir>/<Target>.symbols.json`.
3. The plugin shells out to the bundled `llmref` executable, passing the JSON path and an output path.
4. `llmref` decodes the symbol graph into a minimal Swift schema, groups symbols by their parent type, and emits Markdown — types as `##` headings, members as bullets, doc-comments as indented blocks beneath each bullet.

Synthesized members (e.g. `Error.localizedDescription` inherited from a protocol conformance) are filtered out by the `includeSynthesized: false` option — they bloat the output without adding integration-relevant context.

---

## Components

- **`LLMRefCore`** — pure rendering library. `SymbolGraph` types + `LLMRefRenderer.render(_:) -> String`. No Foundation-Process or I/O — usable as a library in other tools.
- **`llmref`** — CLI executable. `llmref <symbols.json> [output.md]`. Reads the JSON, writes the Markdown. Used by the plugin internally; also runnable standalone if you want to generate refs from a hand-emitted symbol graph.
- **`GenerateLLMRef`** — SPM command plugin. The `generate-llm-ref` verb. Calls `PackageManager.getSymbolGraph` per target, then invokes `llmref`.

---

## License

MIT. See [LICENSE](LICENSE).
