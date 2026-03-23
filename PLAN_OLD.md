# SW³ TextFellow (sw3t): Implementation Plan

## Naming & Branding

| Context | Name |
|---------|------|
| **Long name** | **SW³ TextFellow** (About window, website, docs, App Store listing) |
| **Short name / app name** | **TextFellow** (menu bar, window title, Dock, Finder) |
| **Internal code name / CLI** | **sw3t** (contraction of "sw3" + "textfellow" — reads as "sweet") |
| **CLI alias** | `fellow` (symlink to `sw3t`) |
| **Module prefix** | `SW3T` (e.g., `SW3TTextEngine`, `SW3TRenderer`) |
| **Bundle identifier** | `com.sw3.textfellow` |
| **Config paths** | `~/.config/sw3t/`, `.sw3t/` (project-level) |
| **DMG naming** | `SW3-TextFellow-{version}-{arch}.dmg` |
| **Embeddable package** | `TextFellowKit` |
| **Extension host binary** | `sw3t-extension-host` |
| **Bundle migration CLI** | `sw3t bundle migrate` |

**Name rationale**: "Fellow" is a direct nod to TextMate — both words mean companion/friend, signaling a spiritual successor. It references The Fellowship of the Ring, evoking a diverse group united by a shared mission (open-source, community-driven). And in plain English, it describes the editor's role as a companion that works alongside the developer, not an IDE that replaces judgment. The SW³ prefix (Software³) ties to the broader SW³ brand.

## Context

TextMate is a macOS text editor written entirely in Objective-C++ (159 `.mm`, 290 `.h`, zero Swift), using a custom Rave→Ninja build system, targeting macOS 10.12, and depending on Boost, Cap'n Proto, and Google Sparsehash. SW³ TextFellow is its modern successor — a cross-platform (macOS + iPadOS), SwiftUI-first, Metal-rendered, WASM-sandboxed text editor. This is a **greenfield rewrite**, not an incremental migration. The existing TextMate codebase is preserved in git history; TextFellow is a clean break.

The meeting decisions in SPEC.md define all architectural choices; this plan is the execution roadmap.

## Design Philosophy

**SwiftUI + Metal defaults. Protocol-first architecture. Bleeding edge always. Cross-platform from day one. Open source (GPL-3.0). TextMate's soul, not VS Code's skin.**

### Non-Negotiable Principles

1. **Never use `NSTextView` or `UITextView`** for the editor viewport. Custom Metal rendering only.
2. **Never bypass the `TextStorage` protocol** — no module accesses `BigString` directly.
3. **Never hard-code platform assumptions** — `#if os(...)` only in platform adaptation layers.
4. **50ms launch** — editor is usable before the extension host boots.
5. **Every feature behind a protocol** — `TextStorage`, `SyntaxHighlighter`, `ExtensionHostProtocol`, `BundleSource`, `ConfigProvider`. Concrete implementations are swappable.
6. **No HTML/CSS/Electron** — native rendering only.
7. **Never break iOS support** — all shared modules compile for both platforms at all times.
8. **TextMate's soul, not VS Code's skin** — default state is a clean canvas: text area, tab bar, gutter, status bar. Nothing else. Screenshot next to TextMate 2 should read "same but sharper."
9. **Progressive disclosure** — sidebar hidden by default (⌘1), terminal hidden (⌃\`), command palette hidden (⌘K), all panels slide out completely. Modern features appear only when invoked or contextually relevant. No feature imposes itself. Factory defaults are minimal; `[ui]` settings let users permanently enable features.

### License

**GPL-3.0** — copyleft, community contributions stay open.

### Deliverables

**`README.md`** — Updated with SW³ TextFellow branding, naming rationale, and project vision (immediate, before Phase 1).

**`SPEC.md`** — Living technical specification (update immediately on plan approval with all 14 UI/UX feature specs):
- All architecture decisions with rationale (text engine, rendering, syntax, undo, config, WASM, LSP, terminal)
- What changed vs. classic TextMate and why
- Cross-platform architecture, `ExtensionHostProtocol`, bundle format, capability model
- Ropey (Rust FFI) documented as fallback path if `BigString`/`_RopeModule` becomes untenable
- Migration guide for TextMate bundle authors
- Technology stack summary table
- End-user impact of each modernization

### Version Policy: Always Latest

| Technology | Version | Notes |
|------------|---------|-------|
| macOS deployment | **15.0** (Sequoia) | Latest stable |
| iOS/iPadOS deployment | **18.0** | Matches macOS 15 API surface |
| Swift | **6.x** | Strict concurrency, data-race safety |
| C++ (remaining vendored code) | **C++26 draft** (`-std=c++2c`) | For Onigmo, tree-sitter C runtime |
| Metal | **Metal 3** (`MTLGPUFamily.apple9` primary, `.apple7` floor on AS, `.common3` floor on Intel AMD GPUs) | Per-arch: Metal 3 features on arm64, baseline Metal on x86_64 |
| Xcode | **Latest stable** (16.x+) | Required for Swift 6 |
| CI | `macos-15` runner (arm64) + cross-compile for x86_64 | Per-arch builds, Sparkle/Homebrew handle detection |
| swift-collections | **Latest** | Provides `BigString` (B-tree rope) |
| tree-sitter | **Latest stable** | C runtime + grammars |
| WAMR | **Latest stable** | WASM runtime for extension host |
| ruby.wasm | **Latest stable** | CRuby WASM port |
| WASI | **Preview 2** when available, **Preview 1** floor | Sandbox capabilities |
| SwiftTerm | **Latest** | Embedded terminal |
| Sparkle | **Latest** (v2) | macOS auto-updates |
| Onigmo | **Latest main** | TextMate grammar regex (fallback engine) |

**Per-architecture builds (arm64 and x86_64 as separate binaries). No universal/fat binary.** Sparkle serves the correct architecture via `sparkle:architectures` in the appcast. Homebrew Cask uses `hardware.arch` to select the right download URL. CI builds both architectures in parallel, producing `SW3-TextFellow-arm64.dmg` and `SW3-TextFellow-x86_64.dmg`.

**Versioning**: SemVer (e.g., `2.0.0`) for the editor. Monotonic build number from CI as `CFBundleVersion`. Bundles have independent SemVer versions. Sparkle uses `CFBundleShortVersionString` (SemVer) + `CFBundleVersion` (build number).

### Failure Posture (per-subsystem)

| Subsystem | Failure | Posture |
|-----------|---------|---------|
| **TextStorage** (BigString) | Out-of-bounds, invariant violation | **Crash** — these are programming errors, not recoverable |
| **TextStorage** (BigString) | COW snapshot memory pressure | **Degrade** — evict oldest undo snapshots, log warning |
| **Metal Renderer** | MTLDevice unavailable (CI/headless) | **Degrade** — fall back to no-op renderer for testing |
| **Metal Renderer** | Glyph atlas overflow | **Degrade** — flush LRU, re-rasterize visible glyphs, log perf warning |
| **Metal Renderer** | Shader compilation failure | **Crash** — ship pre-compiled shaders, this should never happen in production |
| **tree-sitter** | Grammar crash / parser hang | **Degrade** — kill parser, fall back to TextMate grammar for that file, notify user |
| **tree-sitter** | No grammar for language | **Degrade** — fall back to TextMate grammar, then to plain text. Silent. |
| **WAMR Extension Host (macOS)** | Crash / hang | **Restart** — detect broken pipe, notify user, respawn host. No editor state lost. |
| **WAMR Extension Host (iOS)** | Crash | **Crash** (app-level) — WASM sandbox makes this unlikely. Acceptable. |
| **WAMR Extension Host** | Script timeout / infinite loop | **Kill** — fuel-based instruction limit, terminate script, notify user |
| **LSP Server** | Crash | **Reconnect** — restart server process, re-send open documents, log |
| **LSP Server** | Malformed JSON-RPC / timeout | **Degrade** — discard response, show stale data, log warning |
| **Config (TOML)** | Parse error in user config | **Degrade** — use defaults for that layer, show diagnostic in editor, log |
| **Config (TOML)** | Missing file | **Silent** — use defaults |
| **File Watcher** | FSEvents flood | **Throttle** — coalesce events with 100ms debounce |
| **File Watcher** | iCloud sync conflict | **Prompt** — show diff dialog, let user choose version |
| **Bundle Loader** | Legacy plist bundle (no capabilities) | **Prompt** — first-run permission dialog: Allow / Restrict / Migrate |

### Observability

All modules use `os_log` with subsystem `com.sw3.textfellow` and per-module categories:

| Category | Covers |
|----------|--------|
| `TextEngine` | TextStorage mutations, snapshot creation, operation log |
| `Renderer` | Frame timing, atlas operations, shader compilation |
| `Syntax` | Parser selection, tree-sitter/TextMate fallback, parse timing |
| `ExtensionHost` | Boot, command execution, IPC, crash/restart |
| `LSP` | Server lifecycle, request/response, errors |
| `Config` | Layer resolution, parse errors, hot-reload |
| `BundleLoader` | Bundle discovery, manifest parsing, capability checks |
| `FileWatcher` | Events, throttling, conflicts |

Zero-cost when not observed. Filterable in Console.app and Instruments.

---

## Phase 1 — Core (First Usable Build)

**Goal**: Text engine + Metal renderer + tree-sitter + basic editing. A minimal but functional editor on macOS.

### 1.1 Project setup

- Xcode project targeting macOS 15.0 + iOS 18.0
- Swift 6 strict concurrency (`SWIFT_STRICT_CONCURRENCY = complete`)
- Swift Package Manager for dependencies: `swift-collections`, `tree-sitter`
- SwiftUI `App` entry point with `@NSApplicationDelegateAdaptor` bridge
- GitHub Actions CI on `macos-15` runner
- Delete legacy: `.travis.yml`, Rave build system (preserved in git history as tagged release)

### 1.2 Text engine: `BigString` behind `TextStorage` protocol

**Replace** the C++ AA-tree text buffer (`oak::basic_tree_t`, `ng::detail::storage_t`, `ng::buffer_t`) with Apple's `BigString` from `swift-collections`.

`BigString` is a B-tree rope in pure Swift — O(log n) insert/delete, copy-on-write snapshots, works on macOS and iOS without FFI.

**Critical**: `BigString` lives in the unstable `_RopeModule` (underscored). Wrap ALL usage behind `TextStorage` protocol:

```swift
protocol TextStorage: Sendable {
    mutating func insert(_ string: String, at index: Index)
    mutating func delete(range: Range<Index>)
    func substring(range: Range<Index>) -> String
    var lineCount: Int { get }
    func line(at index: Int) -> Substring
    func utf16Offset(for index: Index) -> Int
    func snapshot() -> TextStorageSnapshot
}
```

Every module (rendering, undo, syntax highlighting, extension host) talks ONLY to this protocol.

**Fallback path**: If `BigString`/`_RopeModule` breaks, Ropey (Rust B-tree rope) via Swift-Rust FFI is the documented alternative. Conformance spec in SPEC.md.

**Isolation model**: `TextEngineActor` — a dedicated global actor owns all mutable text state. Mutations are `async` calls to the actor. Readers (renderer, tree-sitter, undo) receive immutable COW snapshots via `snapshot()`. No locking, Swift 6 compliant.

**Operation log**: All mutations recorded as insert/delete operations with logical timestamps — foundation for eventual CRDT readiness.

**Crash recovery**: Periodic auto-save to swap file (`.sw3t-swap`) every 5 seconds or 50 edits. On launch, detect orphaned swap files and offer recovery dialog. Check write result — if disk is full, show warning in status bar (never silently lose data).

### 1.3 Metal text rendering

CoreText for shaping, Metal for GPU rendering:

```
SW3TRenderer framework (Swift + Metal):
  ├── GlyphAtlas.swift        — Tiered LRU atlas: 2048² default, 4096² for CJK
  ├── GlyphRasterizer.swift   — CoreText → glyph bitmaps → atlas upload
  ├── TextRenderer.swift      — Metal pipeline: glyph quads with per-vertex syntax colors
  ├── SelectionRenderer.swift — Filled rectangles (selections, caret, backgrounds)
  ├── GutterRenderer.swift    — Line numbers + fold markers
  ├── CursorRenderer.swift    — Smooth cursor animation (position lerp with easing)
  ├── LayoutEngine.swift      — Viewport culling, line metrics from TextStorage
  ├── Shaders.metal           — Vertex/fragment shaders (pre-compiled at build time)
  └── RenderContext.swift     — MTLDevice, MTLCommandQueue, frame management
```

**Glyph atlas sizing**: Start with 2048x2048. If CJK glyphs detected, allocate second 4096x4096 page. LRU eviction per-page.

**Requirements**:
- Full Unicode: ligatures, bidi, RTL (Arabic/Hebrew), CJK, Turkish İ/ı, combined emoji — ALL handled by CoreText
- 120fps on ProMotion, <8ms frame time
- Viewport culling — only visible lines processed
- **Smooth cursor animation** — position lerp between keyframes with easing curve

SwiftUI integration: `MTKView` wrapped in `NSViewRepresentable` / `UIViewRepresentable`.

### 1.4 SW3TViewport — render coordination layer

New shared module that merges text content + syntax tokens + selection state into frame-ready data:

```swift
struct RenderLine {
    let lineNumber: Int
    let glyphRuns: [GlyphRun]     // From CoreText shaping
    let tokens: [HighlightToken]  // From SyntaxHighlighter
    let selections: [Range<Int>]  // Active selections on this line
    let baseline: CGFloat
}

protocol ViewportProvider: Sendable {
    func visibleContent(in rect: CGRect) -> [RenderLine]
    func cursorPositions() -> [CGPoint]
}
```

SW3TRenderer depends ONLY on `ViewportProvider`, not on SW3TTextEngine or SW3TSyntax directly.

**Ownership**: `SW3TDocument` owns `TextStorage`, `SyntaxHighlighter`, `UndoTree`, and theme. `SW3TViewport` is a stateless view-model that queries `SW3TDocument` and produces `RenderLine[]` for the renderer. `ThemeResolver` (injected into both highlighter implementations) maps scope strings to colors — single source of truth for theming.

### 1.5 Syntax highlighting: tree-sitter primary

**tree-sitter** is the primary parsing engine. Incremental parsing, concrete syntax tree, error recovery.

Unified protocol:
```swift
protocol SyntaxHighlighter: Sendable {
    func highlight(in range: Range<TextStorage.Index>, storage: TextStorage) -> [HighlightToken]
    func didEdit(at range: Range<TextStorage.Index>, delta: Int)
}
```

Two implementations:
- `TreeSitterHighlighter` — primary, for languages with tree-sitter grammars
- `TextMateHighlighter` — fallback, using Onigmo regex for `.tmLanguage` grammars

tree-sitter also provides: code folding, scope-aware selection, structural navigation.

**Re-parse strategy** (configurable via `[syntax]` in settings.toml):
- **Default: debounced** — re-parse 50ms after last keystroke. Fast typing gets no highlight updates until pause.
- **Optional: async background** — re-parse on background task after every edit, render with stale tokens until ready (~1-2 frames). Enable via `syntax.incremental_mode = "async"`.

**Parser timeout**: tree-sitter runs with a 2-second timeout. If exceeded (e.g., malformed grammar causes hang), kill parser and fall back to TextMate grammar for that file. Log warning.

### 1.6 Basic editing

- Keyboard input: `NSTextInputClient` (macOS) / `UITextInput` (iOS) on invisible platform view
- Cursor movement, text selection, multi-cursor
- Basic file open/save
- Folder sidebar (SwiftUI `List` with `OutlineGroup`)
- `.editorconfig` support from day one

### 1.7 Undo — design for tree, start with linear

```swift
protocol UndoTree: Sendable {
    func record(operation: EditOperation, snapshot: TextStorageSnapshot)
    func undo() -> TextStorageSnapshot?
    func redo() -> TextStorageSnapshot?
    // Tree navigation (Phase 2):
    // func branches() -> [UndoBranch]
    // func jumpTo(node: UndoNodeID) -> TextStorageSnapshot
}
```

Snapshots are O(1) via `BigString` copy-on-write.

**macOS only in Phase 1.**

---

## Phase 2 — Editor Features & UI/UX

**Goal**: Full editor functionality with TextMate's soul and modern capabilities. Every feature follows progressive disclosure.

### 2.1 Persistent undo tree

Upgrade to full persistent undo tree (Vim-style):
- Every edit creates a branch — user can navigate to any previous state
- O(1) state jump via snapshot swap
- Persist across sessions (serialize to disk, restore on reopen)
- SwiftUI undo tree navigator panel (hidden by default, `⌘⌥U` to open)

### 2.2 TextMate grammar fallback

Integrate Onigmo (vendored C library) for `.tmLanguage` grammar support behind `SyntaxHighlighter` protocol.

### 2.3 Configuration system: layered TOML

**Resolution order** (later overrides earlier):
1. Built-in defaults (hardcoded)
2. User settings: `~/.config/sw3t/settings.toml`
3. `.editorconfig` (cross-editor, per-file via globs)
4. Project settings: `.sw3t/settings.toml` at project root
5. File-type settings: `[filetype.rust]` sections
6. Directory-local: `.sw3t/settings.toml` in subdirectories

JSON Schema for TOML config.

**Theme system — independent chrome and editor themes**:
```toml
[theme]
editor = "Monokai"       # Syntax colors, editor background, cursor, selection
chrome = "system"         # Sidebar, tab bar, status bar, panels, command palette
```
`chrome = "system"` follows macOS/iOS system appearance. Theme hot-reload: file watcher detects changes, re-parses TOML, pushes to Metal renderer and SwiftUI views. No restart.

### 2.4 Command palette (full spec)

The universal entry point for every action. Replaces TextMate's reliance on menu bar navigation.

**Default state**: Invisible. `⌘K` to invoke. iPad: same shortcut with external keyboard, toolbar button without.

**Prefix modes**:
- No prefix → file search (fuzzy match across project files, respecting exclusions)
- `>` → command search (editor commands, bundle commands, settings toggles)
- `@` → symbol search in current file (requires tree-sitter or LSP)
- `:` → go to line number
- `#` → workspace symbol search (cross-file, requires LSP)

Results: filterable list, arrow keys navigate, Enter executes, Escape dismisses. No state retained between invocations.

**Indexing**: Indexes all available actions at launch — built-in commands, bundle commands, LSP commands, user-defined keybinding labels. Re-indexes when bundles installed/updated or LSP capabilities change.

**iPad**: Modal sheet anchored to top of screen (not floating popover). Works with touch and external keyboard.

### 2.5 Search and replace

In-file and project-wide with regex. Smart exclusions by default (`node_modules/`, `.git/`, `build/`, etc.). Configurable via `[indexing]`.

### 2.6 File system watching

macOS: `FSEvents`. iOS: `DispatchSource` + `NSMetadataQuery` for iCloud. Respects exclusions. Reflects external changes immediately.

### 2.7 Snippet engine

TextMate-compatible: tab stops, mirrors, transformations, nested snippets.

### 2.8 Enriched gutter (Metal-rendered, multi-layer)

The gutter is rendered as part of the Metal pass — not a separate UI element.

**Default state**: Line numbers and fold arrows visible. Git indicators and diagnostic icons appear contextually.

**Layers** (left to right):
1. **Git diff bars** — green (added), blue (modified), red (deleted). Appear silently when git repo detected. Click shows inline diff popover.
2. **Diagnostic severity icons** — tiny error/warning/info icons on lines with LSP diagnostics. Click shows detail.
3. **Line numbers** — standard, or relative (`gutter.relative_numbers = true`).
4. **Code folding arrows** — appear on hover over foldable lines (tree-sitter scope boundaries). Click to fold/unfold. Folded regions show `⋯`.

All layers in a single Metal draw pass — zero additional performance cost.

### 2.9 Scope bar (breadcrumb navigation)

**Default state**: Hidden. Enabled via `View > Show Scope Bar` or command palette. Preference persists.

Single row above editor viewport (below tab bar). Each segment clickable — clicking opens a dropdown listing siblings (e.g., clicking a function name shows all functions in the class). Data source: tree-sitter syntax tree for code structure, file path for directory segments.

Replaces the minimap — provides "where am I?" in a compact, actionable format.

### 2.10 Sticky scroll (sticky headers)

**Default state**: Active by default — natural scrolling behavior, no toggle needed.

When scrolling past a scope opening (`func renderFrame() {`), that line pins to the viewport top. Nested scopes stack below. Max depth: 3 lines (`ui.sticky_scroll_max_lines`). Click a sticky line to jump there.

Data source: tree-sitter (not available with TextMate grammar fallback — degrades silently).

### 2.11 Split panes

**Default state**: Single pane. No split UI visible.

- `⌘\` — vertical split
- `⌘⌥\` — horizontal split

**Linked splits**: Same file in two panes shares `TextStorage`, undo tree, syntax state. Edits sync instantly. Scroll positions independent.

**iPad**: Max 2 panes. Orientation follows device (landscape → vertical, portrait → horizontal).

### 2.12 Tab management — preview tabs and pinned tabs

**Preview tabs**: Single-clicking a file opens it as a preview tab (italic title). Navigating to another file replaces the preview. Becomes permanent on edit, double-click, or pin.

**Pinned tabs**: `⌘P` in tab context or right-click → Pin. Collapse to small icon, anchor left. Cannot be `⌘W` closed — must unpin first. Persist across sessions.

### 2.13 Multi-cursor with discoverability

**Core interactions**:
- `⌘D` — select word, then next occurrence (additive)
- `⌥Click` — add cursor at click
- `⌘⇧L` — cursors on all selected lines
- `⌃⇧↑/↓` — add cursor above/below

**Self-retiring hints**: First time user selects a word, status bar shows "⌘D to select next occurrence". After 3 uses across sessions, hint stops. Subtle, non-modal, self-learning.

### 2.14 Zen mode and typewriter mode

**Zen mode** (`⌘⇧↩`): All chrome fades out (~200ms). Only text area remains, centered with generous margins. `⌘⇧↩` or `Escape` restores. No jarring reflow.

**Typewriter mode** (orthogonal, combinable): Active line always vertically centered. Text scrolls up to keep cursor stationary. Enabled via `ui.typewriter_mode = true` or command palette.

### 2.15 Animated transitions

**Hard rule**: No animation >200ms. Animations are cosmetic, never blocking — user can type/click during any animation and it completes instantly.

**Where animations apply**:
- Cursor movement: smooth lerp with ease-out on jumps (go-to-line, click, search nav). Normal typing is instant.
- Panel open/close: spring ~150ms
- Scroll momentum: native platform physics
- Find highlights: matches fade in ~100ms, focused match pulses once
- Tab transitions: new tabs slide in, closed tabs collapse, preview replacement crossfades
- Zen mode: all chrome fades out ~200ms ease-out

**Where animations do NOT apply**: text input, syntax highlighting, diagnostic underlines, scroll position during editing.

### 2.16 Flexible panel system

Panels (terminal, problems, search results, output, undo tree) are dockable containers.

**Default state**: All panels closed. No panel chrome visible.

Panels dock to bottom, left, or right. Each dock supports tabbed panels. Panels draggable between docks or floated (macOS only). Double-click tab to maximize, again to restore.

**iPad**: Panels open as sheets (bottom) or slide-over (side). Panel tabs are swipeable.

**Animation**: Spring ~200ms slide in/out.

### 2.17 Enhanced status bar

Thin, information-dense bar. Always visible (except zen mode).

**Content** (left to right):
- Git branch + sync status (contextual — only when git repo detected)
- `Ln 42, Col 17` (cursor position)
- `3 lines, 147 chars selected` (selection info, only when selected)
- `Spaces: 4` — clickable to change indent style
- `UTF-8` — clickable to change encoding
- `LF` — clickable to change line ending
- `Swift` — clickable to change language
- LSP status: server name + indicator (green/yellow/red)

Every element clickable → inline quick-pick dropdown. Contextual hints for multi-cursor discoverability appear right-side, muted, auto-dismiss.

---

## Phase 3 — Extensibility

**Goal**: WASM bundle runtime, LSP, and the full extension architecture.

### 3.1 WASM extension system

WAMR + ruby.wasm with `ExtensionHostProtocol`:

```swift
protocol ExtensionHostProtocol: Sendable {
    func boot() async throws
    func execute(command: BundleCommand, context: EditorContext) async throws -> CommandResult
    func reload() async throws
    func shutdown() async throws
    var state: AsyncStream<ExtensionHostState> { get }
}
```

- `SubprocessExtensionHost` — macOS (separate process, IPC via Unix socket/XPC)
- `InProcessExtensionHost` — iOS (Swift actor, AOT-only WAMR)

One `#if os(...)` in the factory, nowhere else.

**IPC wire format**: JSON lines (one JSON object per newline) using Swift `Codable` for serialization. Same message types for subprocess IPC and actor calls (actor calls skip serialization). JSON-RPC-like request/response with IDs. Debuggable in Console.app, works over any byte stream (socket, pipe, SSH tunnel for Phase 6).

### 3.2 Bundle format: dual manifest

- `bundle.toml` — modern format with `[capabilities]`
- `info.plist` — classic TextMate fallback (auto-detected, read-only)
- **Legacy bundle first-run prompt**: "This classic bundle requests full access. Allow / Restrict to defaults / Migrate to TOML"
- Capability-gated WASI host API

### 3.3 `sw3t bundle migrate` CLI tool

Plist-to-TOML conversion: `info.plist` → `bundle.toml`, `.tmCommand` → `Commands/*.rb`, `.tmLanguage` → `.tmLanguage.json`, static analysis → inferred `[capabilities]`.

### 3.4 Bundle sources (per-platform)

`BundleSource` protocol: macOS filesystem scanner, iOS container + iCloud scanner.

iCloud bundle sync conflict: **diff dialog** lets user choose which version to keep.

### 3.5 Bundle command output routing

```toml
[[commands]]
output = "terminal"  # or "replace_selection", "show_html", "tooltip", "new_document"
```

### 3.6 LSP client — first-class

Full LSP spec: completion, hover, go-to-definition, find-references, rename, diagnostics, code actions, semantic highlighting, workspace symbols.

**Server lifecycle**: `SW3TLSP` manages a per-language server pool (lazy-spawned, one per workspace). Multi-language projects get multiple servers (e.g., `rust-analyzer` + `typescript-language-server`).

**Token layering**: tree-sitter provides base syntax highlighting. LSP semantic tokens *overlay* additional semantic info (type annotations, macro expansions, unused variable dimming) but never replace tree-sitter's base tokens. Two-layer model, explicit and predictable.

LSP and bundles are **separate, non-overlapping layers**.

### 3.7 Inline diagnostics and ghost text

**Default state**: Active whenever LSP connected. Contextual — no user action to enable.

**Diagnostics**:
- Squiggly underline on affected range (red=error, yellow=warning, blue=info)
- Hover for full message tooltip
- Optional truncated inline summary at line end (`diagnostics.inline_summary = true`, off by default)

**Ghost text** (same Metal glyph pass, reduced opacity):
- LSP/AI completion suggestions — muted color ahead of cursor, Tab to accept
- Snippet placeholder previews — shown when trigger partially typed
- Git blame — optional at line end (`git.inline_blame = true`, off by default)

Ghost text never interferes with actual text editing or selection.

### 3.8 Inline color picker

**Default state**: Active for recognized file types (CSS, SCSS, HTML, SVG, Swift). Contextual.

Small color swatch (~12x12pt) rendered inline by Metal, positioned at end of color literal. Clicking opens system color picker (`NSColorPanel` macOS / `UIColorPickerViewController` iOS). Color updates the literal in real-time.

Scope-aware via tree-sitter — only activates in color contexts, not arbitrary hex strings.

### 3.9 Two-tier distribution

Feature flag `ENABLE_BUNDLES`:
- **Light**: Core editing, tree-sitter, snippets, LSP. No WAMR.
- **Full**: Everything + WAMR + ruby.wasm.

---

## Phase 4 — Platform Expansion

**Goal**: iOS/iPadOS, embedded terminal, CRDT-readiness validation.

### 4.1 iPadOS target

In-process `InProcessExtensionHost`, `UITextInput` bridge, command palette, `.keyboardShortcut()`, customizable toolbar, conservative App Store capabilities (v1: read-only context + text output).

### 4.2 Embedded terminal: SwiftTerm

Toggleable terminal panel, multiple instances, editor theming, bundle output routing.

### 4.3 CRDT-readiness validation

Test operation log with synthetic concurrent operations. Validate COW snapshot semantics under contention. Do NOT build networking.

### 4.4 Platform security

macOS: PrivilegedTool → XPC Service, full App Sandbox (WASM enables this), security-scoped bookmarks.
iOS: App Store sandbox + WASM capability model.
Carbon removal: `kVK_*` via `HIToolbox/Events.h`.

---

## Phase 5 — Distribution

### 5.1 macOS distribution — per-architecture builds

CI produces `SW3-TextFellow-{version}-arm64.dmg` and `SW3-TextFellow-{version}-x86_64.dmg`.

**Sparkle** appcast with `sparkle:architectures`:
```xml
<enclosure url="https://releases.sw3.dev/textfellow/SW3-TextFellow-2.0.0-arm64.dmg"
           sparkle:architectures="arm64" />
<enclosure url="https://releases.sw3.dev/textfellow/SW3-TextFellow-2.0.0-x86_64.dmg"
           sparkle:architectures="x86_64" />
```

**Homebrew Cask**:
```ruby
cask "sw3-textfellow" do
  arch arm: "arm64", intel: "x86_64"
  url "https://releases.sw3.dev/textfellow/SW3-TextFellow-#{version}-#{arch}.dmg"
end
```

Notarization + code signing for both architectures in CI.

### 5.2 iOS distribution — App Store

WASM sandbox ensures review compatibility.

### 5.3 Bundle updates (independent of editor)

Bundle registry, content-addressed `.wasm` files, independent versioning.

### 5.4 Finder/Files integration

macOS: Finder Sync extension ("Open in TextFellow" context menu).
iPadOS: Files app integration for opening folders as projects.

---

## Phase 6 — Platform (Editor as Infrastructure)

**Goal**: Make SW³ TextFellow an editor *platform* that other tools build on.

### 6.1 Embeddable editor component

Package `SW3TTextEngine` + `SW3TRenderer` + `SW3TSyntax` + `SW3TViewport` as a standalone SPM package (`TextFellowKit`) that any macOS/iOS app can embed. Code review tools, database GUIs, CI log viewers, documentation platforms embed it as a view.

Public API surface: `TextStorage`, `SyntaxHighlighter`, `ViewportProvider`, theming, keyboard handling.

### 6.2 Remote extension host

Extend `ExtensionHostProtocol` with a third implementation: `RemoteExtensionHost` — extension host running on a remote machine via SSH/container. Edit locally, run bundles remotely. The IPC abstraction already supports this — swap Unix socket for SSH tunnel.

### 6.3 Multi-language WASM runtimes

Ship Python.wasm (via RustPython) and QuickJS.wasm alongside ruby.wasm. Bundle authors choose their language in `bundle.toml`:
```toml
[bundle]
runtime = "python"  # or "ruby", "javascript"
```

### 6.4 Public Swift plugin API

Expose `TextStorage`, `SyntaxHighlighter`, `ConfigProvider` as public Swift API. Third parties build custom integrations (AI assistants, indexers, custom renderers) as Swift packages, not just WASM scripts.

---

## Xcode Target Structure

**Shared modules (macOS + iOS — zero `#if os(...)`):**

| Target | Type | Contains |
|--------|------|----------|
| `SW3TTextEngine` | Swift Package | `TextStorage` protocol + `BigString` conformance, operation log, undo tree |
| `SW3TViewport` | Framework (Swift) | `ViewportProvider` — merges text + syntax + selection into frame-ready data |
| `SW3TRenderer` | Framework (Swift/Metal) | Glyph atlas (tiered, CJK-aware), Metal pipelines, shaders, cursor animation |
| `SW3TSyntax` | Framework (Swift/C) | `SyntaxHighlighter` protocol, tree-sitter runtime, TextMate grammar engine (Onigmo) |
| `SW3TViews` | Framework (Swift/SwiftUI) | Sidebar, command palette, preferences, find, tab bar, undo tree navigator |
| `SW3TDocument` | Framework (Swift) | Document model, theme system, snippet engine |
| `SW3TConfig` | Framework (Swift) | Layered TOML config, `.editorconfig`, JSON Schema, theme hot-reload |
| `SW3TBundleRuntime` | Framework (Swift) | `ExtensionHostProtocol`, WASI host API, bundle registry, `BundleSource`, TOML + plist loaders |
| `SW3TLSP` | Framework (Swift) | LSP client implementation |
| `SW3TVendor` | Static Lib (C) | Onigmo, tree-sitter runtime, WAMR (when `ENABLE_BUNDLES`) |

**Platform-specific:**

| Target | Platform | Contains |
|--------|----------|----------|
| `SW3TExtensionHost` | macOS only | Subprocess embedding WAMR + ruby.wasm, IPC |
| `SW³ TextFellow` | macOS | SwiftUI App + `SubprocessExtensionHost` + Sparkle |
| `SW³ TextFellow Light` | macOS | SwiftUI App without WAMR |
| `SW³ TextFellow for iPad` | iPadOS | SwiftUI App + `InProcessExtensionHost` (AOT-only) |

---

## Testing Strategy

| Module | Unit Tests | Integration Tests | Snapshot/Visual Tests | Performance Benchmarks |
|--------|-----------|-------------------|----------------------|----------------------|
| `SW3TTextEngine` | Protocol conformance, insert/delete edge cases, nil/empty input, concurrent snapshot access | Operation log replay, undo tree branching | — | BigString at 100MB (insert, delete, line lookup) |
| `SW3TViewport` | RenderLine construction from mock TextStorage + SyntaxHighlighter | Cross-module data flow: edit → re-highlight → render | — | Viewport update latency for 10K-line files |
| `SW3TRenderer` | Glyph atlas LRU eviction, CJK tier-up | — | Metal snapshot comparison (reference images for Latin, CJK, RTL, emoji, ligatures) | Frame time at 120fps with 50K visible glyphs |
| `SW3TSyntax` | tree-sitter incremental re-parse, TextMate fallback selection | Highlight consistency: tree-sitter vs TextMate for same file | — | Re-parse time after single-char edit on 10K-line file |
| `SW3TBundleRuntime` | TOML + plist manifest parsing, capability enforcement, `BundleSource` discovery | WASM command execution round-trip (IPC on macOS, actor on iOS) | — | Cold boot time (AOT + Wizer), warm command execution latency |
| `SW3TLSP` | JSON-RPC message parsing, malformed response handling | Full LSP lifecycle with mock server | — | Request/response latency |
| `SW3TConfig` | Layer resolution order, `.editorconfig` parsing, TOML schema validation | Config change → theme hot-reload → Metal color update | — | — |
| `SW3TDocument` | Snippet expansion, theme parsing | Document open → TextStorage + Syntax + Viewport → rendered frame | — | 100MB file open-to-interactive time |

**Critical path integration test**: Insert text → verify `TextEngineActor` mutation → verify `SyntaxHighlighter` produces tokens → verify `ViewportProvider` produces correct `RenderLine[]`. Uses mock renderer (no GPU required in CI). Covers the keystroke-to-render path across 4 module boundaries.

**Chaos tests**: tree-sitter parser fed random bytes (must timeout, not hang), tree-sitter parser in infinite loop (must timeout at 2s), WAMR extension host executing `while true` (must be killed by fuel limit), LSP server killed mid-response, iCloud conflict during file save, swap file write on full disk (must warn, not silently lose data).

---

## Edge Cases — Platform-Specific Views

| Edge Case | macOS | iPadOS |
|-----------|-------|--------|
| **Text Input** | `NSTextInputClient` on invisible `NSView` | `UITextInput` on invisible `UIView` |
| **Key Equivalent Recorder** | `NSEvent.addLocalMonitorForEventsMatchingMask` | Not needed |
| **HTML Output** | `WKWebView` via `NSViewRepresentable` | `WKWebView` via `UIViewRepresentable` |

Everything else is SwiftUI + Metal, shared across platforms.

---

## Risk Assessment

| Risk | Severity | Mitigation |
|------|----------|------------|
| `BigString` API instability (`_RopeModule`) | **High** | `TextStorage` protocol isolates usage. Ropey (Rust FFI) documented as fallback in SPEC.md. |
| Metal text renderer quality | **Critical** | Prototype glyph atlas first. Validate CJK, RTL, emoji, ligatures. Tiered atlas sizing. Reference Zed's gpui. Metal snapshot tests. |
| tree-sitter grammar coverage | **Medium** | TextMate grammar fallback. Both behind `SyntaxHighlighter` protocol. |
| Swift 6 strict concurrency on C interop | **High** | tree-sitter and WAMR need `@unchecked Sendable` wrappers. Budget time. |
| iOS App Store review (WASM runtime) | **Medium** | AOT-only, no JIT, no private APIs. Conservative v1 capabilities. |
| SwiftUI performance for large file trees | **Medium** | Profile `OutlineGroup` with 10K+ nodes. Platform list view fallback if needed. |
| Per-arch build/release matrix | **Low** | CI builds both in parallel. Sparkle + Homebrew handle detection. |
| WASM capability escalation via plist | **Medium** | First-run permission prompt for legacy bundles. |
| iCloud bundle sync conflicts | **Medium** | Diff dialog for user choice. |

---

## Verification Plan

After each phase, verify on **both platforms**:

1. **Build**: Xcode succeeds for macOS arm64, macOS x86_64, and iPadOS arm64 — Swift 6, zero warnings
2. **Tests**: All pass in Swift Testing (`@Test`, `#expect`), including chaos tests
3. **50ms launch**: Editor usable before extension host boots
4. **Protocol boundaries**: No module accesses `BigString` directly — module boundary audit
5. **Metal rendering**: CJK/RTL/emoji/ligatures correct, 120fps ProMotion, tiered atlas works
6. **tree-sitter**: Incremental re-parse correct, fallback to TextMate grammar works
7. **Bundle commands**: Subprocess (macOS) and in-process actor (iPadOS) both execute via WASM
8. **Bundle format**: Same `.bundle` loads on macOS and iPad (iCloud sync test)
9. **Legacy bundle prompt**: First-run permission dialog fires for plist-only bundles
10. **Config**: Layered TOML, `.editorconfig`, theme hot-reload, JSON Schema validates
11. **LSP**: Completion, diagnostics, go-to-definition with `rust-analyzer`
12. **Input**: CJK IME, emoji, dictation on both platforms
13. **Code signing**: `codesign --verify` on both arm64 and x86_64 DMGs. iPadOS provisioning for TestFlight
14. **Accessibility**: VoiceOver on both platforms
15. **Metal validation**: Zero errors with validation layer
16. **os_log**: Structured logs for all subsystems, filterable in Console.app

---

## Summary Timeline

| Phase | Scope | Key Deliverable |
|-------|-------|-----------------|
| 0 | SPEC.md | Living specification — all decisions documented |
| 1 | Core | `BigString`/`TextStorage`, Metal renderer (tiered atlas, cursor animation), tree-sitter, `SW3TViewport`, basic editing (macOS) |
| 2 | Editor Features & UI/UX | Undo tree, TOML config (theme separation + hot-reload), command palette (prefix modes), search, snippets, enriched gutter, scope bar, sticky scroll, split panes, preview/pinned tabs, multi-cursor, zen/typewriter mode, flexible panels, animated transitions, enhanced status bar |
| 3 | Extensibility | WAMR + ruby.wasm, `ExtensionHostProtocol`, bundle format, LSP client, inline diagnostics + ghost text, inline color picker |
| 4 | Platform Expansion | iPadOS, SwiftTerm terminal, CRDT-readiness validation, App Sandbox |
| 5 | Distribution | Sparkle (per-arch), App Store, Homebrew Cask, Finder/Files integration |
| 6 | Platform | Embeddable `TextFellowKit` SPM package, remote extension host, multi-language WASM, public Swift plugin API |

Each phase produces a usable editor. Four build products from single codebase: SW³ TextFellow (macOS Full), SW³ TextFellow Light (macOS), SW³ TextFellow for iPad, TextFellowKit (embeddable SPM package).

---

## Default Keybinding Map (TextMate Heritage)

| Action | macOS | iPad (external keyboard) |
|--------|-------|--------------------------|
| Command palette | `⌘K` | `⌘K` |
| File search (quick open) | `⌘T` | `⌘T` |
| Toggle sidebar | `⌘1` | `⌘1` |
| Toggle terminal | `` ⌃` `` | `` ⌃` `` |
| Zen mode | `⌘⇧↩` | `⌘⇧↩` |
| Vertical split | `⌘\` | `⌘\` |
| Horizontal split | `⌘⌥\` | — |
| Go to line | `⌘L` | `⌘L` |
| Go to symbol | `⌘⇧O` | `⌘⇧O` |
| Select next occurrence | `⌘D` | `⌘D` |
| Add cursor above/below | `⌃⇧↑/↓` | `⌃⇧↑/↓` |
| Cursors on all lines | `⌘⇧L` | `⌘⇧L` |
| Fold/unfold | `⌘⌥[` / `⌘⌥]` | `⌘⌥[` / `⌘⌥]` |
| Undo tree navigator | `⌘⌥U` | `⌘⌥U` |
| Run last bundle command | `⌘⇧R` | `⌘⇧R` |

All keybindings remappable in `~/.config/sw3t/keybindings.toml`.

---

## Progressive Disclosure: Default States

| Feature | Default | Activation |
|---------|---------|------------|
| Command palette | Hidden | `⌘K` |
| Sidebar | Closed | `⌘1` |
| Scope bar | Off | View menu / command palette |
| Sticky scroll | On (natural) | Appears during scrolling |
| Inline diagnostics | On (contextual) | Appears when LSP connected |
| Git gutter | On (contextual) | Appears when git detected |
| Ghost text | On (contextual) | Appears when LSP/AI available |
| Multi-cursor hints | On (self-retiring) | Status bar, stops after 3 uses |
| Split panes | Single pane | `⌘\` |
| Preview tabs | On (natural) | During file browsing |
| Terminal panel | Closed | `` ⌃` `` |
| Zen mode | Off | `⌘⇧↩` |
| Typewriter mode | Off | Settings or command palette |
| Color picker | On (contextual) | Appears near color literals |
| Animated transitions | On | Always (<200ms) |
| Theme separation | System default | `[theme]` in settings |
