# SW³ TextFellow

A modern, cross-platform text editor for macOS and iPadOS — the spiritual successor to [TextMate](https://macromates.com/). Built with SwiftUI, Metal, and a WASM-sandboxed extension system.

**Internal code name:** `sw3t` (reads as "sweet")

## Naming and Branding

The editor's public name is **SW³ TextFellow** and its internal code name is **sw3t** (a contraction of "sw3" + "textfellow" that conveniently reads as "sweet"). The name operates on three levels: "Fellow" is a direct nod to TextMate — both words mean companion/friend, signaling that this is a spiritual successor to TextMate's philosophy of lightweight, scriptable, bundle-driven editing; it is also a reference to The Fellowship of the Ring, evoking the idea of a diverse group united by a shared mission, which mirrors the project's open-source, community-driven ethos; and finally, "Fellow" in its plain English sense describes the editor's role as a companion that works alongside the developer, not an IDE that tries to replace the developer's judgment. The SW³ prefix (Software³) ties the editor to the broader SW³ brand and content ecosystem. Use `sw3t` as the CLI binary name (with `fellow` alias), internal module prefix. Use "SW³ TextFellow" in user-facing contexts: the About window, website, documentation, and App Store listing.

## Vision

SW³ TextFellow is a greenfield rewrite of TextMate, built from scratch with modern Apple technologies:

- **SwiftUI + Metal** — native UI with GPU-accelerated text rendering
- **tree-sitter** — incremental parsing for syntax highlighting, code folding, and structural navigation
- **WASM-sandboxed bundles** — TextMate-compatible extension system running Ruby scripts safely via WebAssembly
- **Cross-platform** — macOS and iPadOS from a single codebase
- **Protocol-first** — every subsystem behind a swappable protocol (`TextStorage`, `SyntaxHighlighter`, `ExtensionHostProtocol`, etc.)
- **LSP support** — first-class Language Server Protocol client
- **50ms launch** — editor is usable before the extension host boots

## Architecture

See [SPEC.md](SPEC.md) for the full technical specification.

| Layer | Technology |
|-------|-----------|
| Text engine | `BigString` from `swift-collections` (behind `TextStorage` protocol) |
| Rendering | Metal via `MTKView` (glyph atlas, CoreText shaping) |
| Syntax | tree-sitter (primary) + TextMate grammars/Onigmo (fallback) |
| UI | SwiftUI (everything except editor viewport) |
| Extensions | WAMR + ruby.wasm (WASI-sandboxed) |
| Terminal | SwiftTerm |
| Config | Layered TOML + `.editorconfig` |

## Build Products

| Product | Platform | Description |
|---------|----------|-------------|
| SW³ TextFellow | macOS | Full editor with WASM bundle runtime |
| SW³ TextFellow Light | macOS | Core editor without bundle command execution |
| SW³ TextFellow for iPad | iPadOS | Full editor with in-process WASM runtime |
| TextFellowKit | SPM Package | Embeddable editor component for third-party apps |

## Building

*Build instructions will be added as the project scaffolding is set up in Phase 1.*

## Legacy TextMate

The original TextMate codebase (Objective-C++, Rave build system) is preserved in git history. SW³ TextFellow is a clean break — a new editor that inherits TextMate's bundle ecosystem and philosophy, not its code.

## Legal

The source for SW³ TextFellow is released under the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

TextMate is a trademark of Allan Odgaard.
