# SW³ TextFellow — Technical Specification

> **Long name:** SW³ TextFellow | **Short name / app name:** TextFellow | **Code name:** sw3t | **License:** GPL-3.0

This is the living technical specification for SW³ TextFellow, the modern successor to TextMate. Every architectural decision is documented here with rationale. Updated continuously as decisions are made during implementation.

---

## 0. UI/UX Philosophy: TextMate's Soul, Modern Capabilities

### Decision: Progressive disclosure — clean canvas by default

The default appearance of SW³ TextFellow must be visually indistinguishable from a slightly refined TextMate. On first launch, the user sees:

- A text area
- A tab bar
- A gutter with line numbers and fold markers
- A thin status bar at the bottom

**Nothing else.** No sidebar, no terminal panel, no breadcrumb bar, no minimap, no activity bar. The editor trusts the user — it provides a clean canvas and lets them summon tools as needed.

```
  Default state (what the user sees on first launch):

  ┌──────────────────────────────────────────────┐
  │ Title Bar                                     │
  ├──────────────────────────────────────────────┤
  │ Tab Bar                                       │
  ├────┬─────────────────────────────────────────┤
  │ 1  │                                         │
  │ 2  │  (text area — the primary citizen)       │
  │ 3  │                                         │
  │ 4  │                                         │
  │ 5  │                                         │
  │ 6  │                                         │
  ├────┴─────────────────────────────────────────┤
  │ Line:1:1 │ Plain Text │ Spaces:4 │           │
  └──────────────────────────────────────────────┘

  NOT shown by default:
  ✗ Sidebar          (⌘1 to toggle)
  ✗ Terminal panel   (⌃` to toggle)
  ✗ Scope bar        (View menu to enable)
  ✗ Minimap          (View menu to enable)
  ✗ Breadcrumbs      (View menu to enable)
  ✗ Activity bar     (never — not in the design)
```

### Decision: Every modern feature follows progressive disclosure

All features described in this spec — command palette, scope bar, sticky scroll, inline diagnostics, git gutter, split panes, terminal, zen mode, undo tree navigator — are **hidden by default** and appear only when:

1. **Invoked** — via keybinding or command palette
2. **Contextually relevant** — git gutter appears silently when a git repo is detected; inline diagnostics appear when an LSP server connects; sticky scroll activates naturally during scrolling

No feature announces itself. No feature consumes screen space when not in use. The text area is always the primary citizen — every panel, sidebar, and overlay exists in service of the text, never competing with it.

### Decision: Default keybindings for feature discovery

| Feature | Keybinding | Default State |
|---------|------------|---------------|
| Command palette | `⌘K` | Hidden |
| File browser sidebar | `⌘1` | Hidden |
| Terminal panel | `⌃\`` | Hidden |
| Scope bar / breadcrumbs | View → Scope Bar | Hidden |
| Zen mode (distraction-free) | `⌘⇧↩` | Off |
| Undo tree navigator | `⌘⌥U` | Hidden |
| Split pane | `⌘\\` | Single pane |
| Go to file | `⌘T` | Hidden |
| Go to symbol | `⌘⇧T` | Hidden |
| Go to line | `⌘L` | Hidden |

Panels slide in with subtle spring animations and slide out completely — no residual chrome.

### Decision: User-configurable defaults via `[ui]` settings

Users can permanently enable features in `settings.toml`:

```toml
[ui]
sidebar = true           # Show sidebar on launch
terminal = false          # Keep terminal hidden (default)
scope_bar = false         # Keep breadcrumbs hidden (default)
minimap = false           # Keep minimap hidden (default)
line_numbers = true       # Show line numbers (default: true)
fold_markers = true       # Show fold markers (default: true)
git_gutter = "auto"       # "auto" (show when git repo detected), "always", "never"
sticky_scroll = true      # Enable sticky scroll (default: true, activates contextually)
```

But the **factory defaults** feel like TextMate with a fresh coat of paint, not like VS Code with a TextMate skin.

### Decision: Visual identity test

> If someone screenshots the default state of SW³ TextFellow and posts it next to a screenshot of TextMate 2, the reaction should be "oh it looks the same but sharper" — not "oh it looks like VS Code."

The modern features are discoverable through:
- The command palette (`⌘K`)
- Contextual hints in the status bar
- Documentation and first-run tips

But they never impose themselves on a user who just wants to open a file and edit text.

### Feature Specifications

#### Command Palette
Universal entry point. Hidden by default, `⌘K` to invoke. Prefix modes: none=files, `>`=commands, `@`=symbols, `:`=line, `#`=workspace symbols. iPad: modal sheet at top, works with touch + external keyboard. Indexes all actions at launch, re-indexes on bundle/LSP changes.

#### Scope Bar (Breadcrumbs)
Hidden by default (View menu to enable). Single row above editor showing cursor's structural context. Segments clickable → sibling dropdown. Data: tree-sitter syntax tree + file path. Replaces minimap.

#### Inline Diagnostics & Ghost Text
Active contextually when LSP connected. Squiggly underlines (red/yellow/blue), hover tooltips. Ghost text (reduced opacity Metal pass): LSP completions (Tab to accept), snippet previews, optional git blame (`git.inline_blame = true`).

#### Sticky Scroll
Active by default (natural behavior). Scope headers pin to viewport top when scrolled past. Nested scopes stack (max 3, configurable). Click to jump. tree-sitter only — degrades silently without it.

#### Split Panes
Single pane default. `⌘\` vertical, `⌘⌥\` horizontal. Linked splits share TextStorage/undo/syntax — edits sync, scroll independent. iPad: max 2 panes.

#### Tab Management
Preview tabs: single-click opens italic preview, replaced on navigation. Permanent on edit/double-click/pin. Pinned tabs: icon-only, anchored left, immune to `⌘W`, persist across sessions.

#### Zen Mode & Typewriter Mode
Zen (`⌘⇧↩`): all chrome fades ~200ms, text centered. Escape/`⌘⇧↩` restores. Typewriter (orthogonal): active line centered, text scrolls up. `ui.typewriter_mode = true`.

#### Inline Color Picker
Active by default for CSS/SCSS/HTML/SVG/Swift. 12x12pt swatch at color literal end. Click → system picker. Scope-aware via tree-sitter.

#### Enriched Gutter
Metal-rendered, 4 layers: git diff bars (contextual) → diagnostic icons (contextual) → line numbers → fold arrows (hover). Single draw pass.

#### Multi-Cursor
`⌘D` next occurrence, `⌥Click` add cursor, `⌘⇧L` all selected lines, `⌃⇧↑/↓` above/below. Self-retiring status bar hints (stop after 3 uses).

#### Flexible Panel System
All closed by default. Dockable bottom/left/right, tabbed, draggable, floatable (macOS). iPad: sheets/slide-over. Spring ~200ms animations.

#### Enhanced Status Bar
Always visible (except zen). Git branch, cursor pos, selection info, indent/encoding/EOL/language (all clickable), LSP status. Contextual hints right-side.

#### Animated Transitions
Hard rule: <200ms, never blocking. Cursor lerp on jumps, panel spring, scroll momentum, find highlight fade, tab slide, zen fade. NOT: text input, syntax colors, diagnostics, edit scrolling.

#### Theme System
Independent chrome and editor themes: `[theme] editor = "Monokai"`, `chrome = "system"`. Hot-reload on file change.

### Progressive Disclosure Defaults

| Feature | Default | Activation |
|---------|---------|------------|
| Command palette | Hidden | `⌘K` |
| Sidebar | Closed | `⌘1` |
| Scope bar | Off | View menu |
| Sticky scroll | On (natural) | During scrolling |
| Inline diagnostics | On (contextual) | With LSP |
| Git gutter | On (contextual) | In git repos |
| Ghost text | On (contextual) | With LSP/AI |
| Multi-cursor hints | On (self-retiring) | Status bar |
| Split panes | Single | `⌘\` |
| Preview tabs | On (natural) | During browsing |
| Terminal | Closed | `` ⌃` `` |
| Zen mode | Off | `⌘⇧↩` |
| Color picker | On (contextual) | Near color literals |
| Animations | On | Always (<200ms) |

---

## 1. Text Engine

### Decision: Apple's `BigString` from `swift-collections`

The core text storage is `BigString`, a B-tree rope from the `swift-collections` package. It provides O(log n) insertion/deletion, copy-on-write snapshots, and works on both macOS and iOS without FFI.

**`BigString` lives in the unstable `_RopeModule`** (underscored API). All usage is wrapped behind a `TextStorage` protocol. No module outside `SW3TTextEngine` touches `BigString` directly.

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

**Why BigString over alternatives:**
- Pure Swift — no C++ FFI, no bridging overhead
- B-tree rope — O(log n) for all operations on large documents
- Copy-on-write — O(1) snapshots for undo and concurrent access
- Apple-maintained — aligned with the Swift ecosystem direction

**Fallback path:** If `_RopeModule` is removed or breaks, Ropey (Rust B-tree rope) via Swift-Rust FFI is the documented alternative. Only the `TextStorage` conformance layer changes — nothing else is affected.

### Decision: `TextEngineActor` isolation model

A dedicated global actor (`TextEngineActor`) owns all mutable text state:
- Mutations are `async` calls to the actor
- Readers (renderer, tree-sitter, undo) receive immutable COW snapshots via `snapshot()`
- No locking, fully Swift 6 compliant

```
                    ┌─────────────────────┐
                    │  TextEngineActor     │
                    │  (owns mutable state)│
   insert/delete ──►│                     │──► snapshot() ──► Renderer
   (main thread)    │  BigString          │──► snapshot() ──► tree-sitter
                    │  OperationLog       │──► snapshot() ──► Undo
                    └─────────────────────┘
```

### Decision: Batched mutations via `EditBatch`

The actor's public API accepts batched operations to avoid per-mutation async overhead. Instead of calling `insert()` N times for N cursors (N actor round-trips), the caller assembles an `EditBatch` and sends a single `apply(batch:)` call. The actor processes the batch atomically, produces one snapshot, and records one undo entry.

Use cases: multi-cursor editing, find-and-replace, large paste operations.

**Performance target:** 50 simultaneous cursors inserting a character on a 100K-line file must complete within 8ms (one frame at 120fps).

```swift
var batch = EditBatch()
batch.insert("x", at: cursor1Offset)
batch.insert("x", at: cursor2Offset)
batch.insert("x", at: cursor3Offset)
await session.apply(batch: batch) // one actor call, one snapshot, one undo entry
```

### Decision: Operation log for CRDT readiness

Every mutation is recorded as an insert/delete operation with a logical timestamp. This is not for collaborative editing today — it ensures we don't close the door on it. No CRDT resolution, no networking, just the invariant that every mutation is a replayable operation.

### Decision: Crash recovery via swap files

Periodic auto-save to `.sw3t-swap` file every 5 seconds or 50 edits. On launch, orphaned swap files trigger a recovery dialog. Write failures (disk full) show a warning in the status bar — never silently lose data.

---

## 2. Rendering

### Decision: GPU-accelerated text rendering via Metal

No `NSTextView` or `UITextView`. Custom Metal rendering pipeline:

1. **Text shaping/layout:** Delegated entirely to CoreText (`CTTypesetter`, `CTLine`, `CTRun`). CoreText handles ligatures, bidi, RTL, CJK, emoji, font fallback, OpenType features.
2. **Glyph atlas:** LRU-cached GPU texture atlas. Tiered sizing — 2048x2048 default, 4096x4096 second page allocated when CJK glyphs are detected.
3. **Metal renderer:** `MTKView` as rendering surface. Each frame: extract visible lines (viewport culling), run CoreText layout, emit vertex buffer of textured glyph quads with per-vertex syntax colors.
4. **SwiftUI integration:** `MTKView` wrapped in `NSViewRepresentable` (macOS) / `UIViewRepresentable` (iOS). Only the editor viewport is Metal — everything else is SwiftUI.

**Performance targets:**
- 120fps on ProMotion displays
- <8ms frame time for full viewport redraw
- Sub-millisecond incremental updates

**Smooth cursor animation:** Position lerp between keyframes with easing curve. Metal-rendered, follows the Zed model.

### Decision: `SW3TViewport` coordination layer

`SW3TViewport` merges text + syntax + selection into frame-ready `RenderLine` structs. The renderer depends only on the `ViewportProvider` protocol — never on `SW3TTextEngine` or `SW3TSyntax` directly.

**Ownership model:** `SW3TDocument` owns `TextStorage`, `SyntaxHighlighter`, `UndoTree`, and theme. `SW3TViewport` is a stateless view-model that reads from `SW3TDocument` and produces `RenderLine[]`.

```
  SW3TDocument (owns state)
       │
       ▼
  SW3TViewport (stateless view-model)
       │
       ▼
  [RenderLine] ──► SW3TRenderer (Metal draw)
```

---

## 3. Syntax Highlighting

### Decision: tree-sitter primary, TextMate grammars as fallback

**tree-sitter** is the primary parsing engine. Incremental parsing, concrete syntax tree, error recovery. Industry standard (Zed, Neovim, Emacs 29, GitHub).

**TextMate grammars** (`.tmLanguage` / `.tmLanguage.json`) are the fallback for languages without tree-sitter parsers. Hundreds of niche languages have TextMate grammars but no tree-sitter parser.

Both implementations conform to a unified `SyntaxHighlighter` protocol:

```swift
protocol SyntaxHighlighter: Sendable {
    func highlight(in range: Range<TextStorage.Index>, storage: TextStorage) -> [HighlightToken]
    func didEdit(at range: Range<TextStorage.Index>, delta: Int)
}
```

**Selection logic:** tree-sitter grammar exists → use it. Otherwise → TextMate grammar (Onigmo regex). Neither → plain text.

**ThemeResolver:** Injected into both highlighter implementations. Maps scope strings to colors. Single source of truth for theming.

### Decision: Re-parse strategy (configurable)

- **Default: debounced** — re-parse 50ms after last keystroke
- **Optional: async background** — re-parse on background task after every edit, render with stale tokens until ready. Enable via `syntax.incremental_mode = "async"` in settings.toml.

**Parser timeout:** 2 seconds. If exceeded, kill parser and fall back to TextMate grammar for that file.

### Decision: LSP semantic token layering

tree-sitter provides base syntax highlighting. LSP semantic tokens *overlay* additional info (type annotations, macro expansions, unused variable dimming) but never replace tree-sitter's base tokens. Two-layer model.

---

## 4. Configuration System

### Decision: TOML primary, plist fallback, layered resolution

**Resolution order** (later overrides earlier):
1. Built-in defaults (hardcoded)
2. User settings: `~/.config/sw3t/settings.toml`
3. `.editorconfig` (cross-editor, per-file via globs)
4. Project settings: `.sw3t/settings.toml` at project root
5. File-type settings: `[filetype.rust]` sections
6. Directory-local: `.sw3t/settings.toml` in subdirectories

JSON Schema provided for TOML config — enables autocompletion in any LSP-capable editor.

Plist support for bundle manifests only (auto-detected, read-only). The editor never writes plist, only TOML.

### Decision: `.editorconfig` support from day one

Non-negotiable baseline. Sits between project settings and file-type settings in the resolution order.

### Decision: Theme hot-reload

File watcher watches theme files. On change, re-parse TOML, update Metal render colors live.

---

## 5. Undo System

### Decision: Persistent undo tree with structural sharing

Not linear undo. A persistent undo tree (Vim-style) where every edit creates a branch. Users can navigate to any previous state.

Integration with BigString's COW snapshots:
- Creating a snapshot is O(1) — increment reference count on tree root
- Jumping to any undo state is O(1) — swap the active snapshot
- Memory proportional to actual differences (structural sharing)
- Undo tree persists across sessions (serialized to disk)

SwiftUI undo tree navigator panel for visual branch exploration.

---

## 6. Project and File Management

### Decision: Folder-based with real-time file watching

Open a directory = your project. No project files required.

**File watching:**
- macOS: `FSEvents` via `DispatchSource.makeFileSystemObjectSource`
- iOS: `DispatchSource` for container files + `NSMetadataQuery` for iCloud

External file changes reflected immediately with non-intrusive notification if unsaved changes exist.

### Decision: Smart indexing with configurable exclusions

Default exclusions: `node_modules/`, `.git/`, `build/`, `dist/`, `.next/`, `__pycache__/`, `.cache/`, `target/`, `Pods/`

User-configurable:
```toml
[indexing]
exclude = ["node_modules", ".git", "build", "dist", "vendor"]
include_override = ["vendor/our-fork"]
```

File watcher respects exclusions — excluded directories are not watched.

---

## 7. WASM Extension System

### Decision: WAMR + ruby.wasm, VS Code extension host architecture

Replace TextMate's "spawn Ruby subprocess" model with:
- **WAMR** (WebAssembly Micro Runtime) embedded as the WASM engine
- **ruby.wasm** (official CRuby WASM port) as the language runtime
- **Extension host subprocess** (macOS) or in-process actor (iOS)

### Decision: `ExtensionHostProtocol` — single platform abstraction

```swift
protocol ExtensionHostProtocol: Sendable {
    func boot() async throws
    func execute(command: BundleCommand, context: EditorContext) async throws -> CommandResult
    func reload() async throws
    func shutdown() async throws
    var state: AsyncStream<ExtensionHostState> { get }
}
```

Two implementations:
- `SubprocessExtensionHost` — macOS (separate process, IPC via Unix socket/XPC)
- `InProcessExtensionHost` — iOS (Swift actor, AOT-only WAMR)

Exactly one `#if os(...)` in the factory. Nowhere else.

### Decision: iOS extension host crash recovery

On iOS, the extension host runs in-process. A bug in WAMR itself (not in the Ruby script) could crash the app. Defensive layer:

1. Run the WAMR runtime on a **dedicated, isolated thread** (not main, not the actor's thread)
2. Wrap execution in a **signal handler** (`SIGSEGV`, `SIGBUS`) that catches low-level faults
3. On fault: mark extension host as crashed, tear down WAMR thread, post UI notification: "Bundle system encountered an error and was restarted"
4. Main app and editor state remain intact

This turns a full app crash into a recoverable extension host restart. Not as robust as macOS subprocess isolation (truly fatal WAMR corruption could still propagate), but covers the most common crash scenarios.

### Decision: IPC wire format — JSON lines + Codable

JSON-RPC-like protocol: one JSON object per newline, Swift `Codable` for serialization. Actor calls skip serialization (same types). Works over any byte stream (socket, pipe, SSH tunnel for remote host).

### Decision: Two-tier distribution

Compile-time feature flag `ENABLE_BUNDLES`:
- **Light Edition:** Core editing, tree-sitter, snippets, LSP. No WAMR.
- **Full Edition:** Everything + WAMR + ruby.wasm + extension host.

### Decision: Cold-start mitigation

| Strategy | Effect |
|----------|--------|
| Pre-warming | Spawn host 2s after UI ready |
| AOT compilation | `wamrc` pre-compiles ruby.wasm to native arm64 at install time |
| Wizer pre-initialization | Snapshot Ruby interpreter after boot |
| Module caching | WAMR caches compiled modules to disk |

### Decision: WASI capability model

Bundles declare required permissions in `bundle.toml`:
```toml
[capabilities]
read_selection = true
replace_selection = true
read_file = true
write_file = false
network = false
filesystem_scope = "project"
```

### Decision: Legacy bundle security — first-run permission prompt

Classic plist-based bundles (no `[capabilities]` declaration) trigger a first-run dialog: "This classic bundle requests full access. Allow / Restrict to defaults / Migrate to TOML." Per-bundle decision stored persistently.

---

## 8. Bundle Format

### Decision: Dual manifest — TOML primary, plist fallback

Runtime loader auto-detects: `bundle.toml` exists → use it. Otherwise → `info.plist` fallback.

**Modern bundle (TOML):**
```
MyLanguage.bundle/
├── bundle.toml
├── Syntaxes/*.tmLanguage.json
├── Snippets/*.sublime-snippet
├── Commands/*.rb
├── Preferences/*.tmPreferences
└── Support/lib/*.rb
```

**Classic TextMate bundle (plist):**
```
MyLanguage.tmbundle/
├── info.plist
├── Syntaxes/*.tmLanguage
├── Snippets/*.tmSnippet
├── Commands/*.tmCommand
├── Preferences/*.tmPreferences
└── Support/lib/*.rb
```

Both load into the same `BundleManifest` in-memory representation.

### Decision: `sw3t bundle migrate` CLI tool

Plist-to-TOML conversion pipeline:
- `info.plist` → `bundle.toml`
- `.tmCommand` → `Commands/*.rb` + TOML entry
- `.tmSnippet` → `.sublime-snippet`
- `.tmLanguage` (XML plist) → `.tmLanguage.json`
- Static analysis → inferred `[capabilities]`

### Decision: Bundle sources — per-platform

`BundleSource` protocol with platform implementations:
- macOS: `~/Library/Application Support/TextMate/Bundles/`, app bundle, user-configured paths
- iOS: app container, Documents, iCloud Drive (`TextFellow/Bundles/`)

iCloud sync conflicts: diff dialog lets user choose which version to keep.

---

## 9. LSP

### Decision: First-class LSP support

Built-in LSP client supporting the full LSP specification. LSP and bundles are separate, non-overlapping layers:
- **Bundles:** syntax highlighting, snippets, text transformations, commands, scripting
- **LSP:** language intelligence (completion, diagnostics, navigation, refactoring)

### Decision: Server lifecycle

`SW3TLSP` manages a per-language server pool (lazy-spawned, one per workspace). Multi-language projects get multiple servers.

### Decision: Token layering

tree-sitter provides base syntax highlighting. LSP semantic tokens overlay additional semantic info but never replace tree-sitter's base tokens.

Per-language config:
```toml
[language.rust]
lsp = "rust-analyzer"
```

---

## 10. Terminal

### Decision: SwiftTerm embedded terminal

Toggleable terminal panel with multiple instances (tabs). Integrates with editor theming. Bundle command output optionally routable to terminal:

```toml
[[commands]]
output = "terminal"
```

---

## 11. Cross-Platform Architecture

### Decision: macOS + iPadOS from single codebase

All shared modules compile for both platforms with **zero `#if os(...)` conditionals**. Platform divergence confined to:

1. **Extension host process model:** Subprocess (macOS) vs in-process actor (iOS)
2. **WAMR execution mode:** Full range on macOS, AOT-only on iOS (W^X policy)
3. **Text input bridge:** `NSTextInputClient` (macOS) vs `UITextInput` (iOS)

### Decision: Platform-specific views (only 3)

| Edge Case | macOS | iPadOS |
|-----------|-------|--------|
| Text Input | `NSTextInputClient` on invisible `NSView` | `UITextInput` on invisible `UIView` |
| Key Equivalent Recorder | `NSEvent.addLocalMonitorForEventsMatchingMask` | Not needed |
| HTML Output | `WKWebView` via `NSViewRepresentable` | `WKWebView` via `UIViewRepresentable` |

Everything else is SwiftUI + Metal, shared.

---

## 12. Distribution

### Decision: Per-architecture builds

arm64 and x86_64 as separate binaries. No universal/fat binary.
- **Sparkle:** `sparkle:architectures` in appcast for automatic detection
- **Homebrew Cask:** `hardware.arch` for correct download URL
- **Versioning:** SemVer + monotonic CI build number

### Decision: Sparkle on macOS, App Store on iOS

macOS: DMG + Sparkle auto-updates + Homebrew Cask. Notarized in CI.
iOS: App Store only. WASM sandbox ensures review compatibility.

### Decision: Independent bundle updates

Bundle registry with own update mechanism. Bundles are versioned and content-addressed.

---

## 13. Failure Posture

| Subsystem | Failure | Posture |
|-----------|---------|---------|
| TextStorage | Out-of-bounds / invariant | **Crash** (programming error) |
| TextStorage | COW memory pressure | **Degrade** (evict old snapshots, warn) |
| Metal Renderer | MTLDevice unavailable | **Degrade** (no-op renderer for CI) |
| Metal Renderer | Glyph atlas overflow | **Degrade** (flush LRU, re-rasterize) |
| Metal Renderer | Shader failure | **Crash** (pre-compiled, should never happen) |
| tree-sitter | Grammar crash / hang | **Degrade** (2s timeout, fall back to TextMate grammar) |
| tree-sitter | No grammar | **Degrade** (TextMate grammar → plain text) |
| Extension Host (macOS) | Crash | **Restart** (respawn subprocess) |
| Extension Host (iOS) | Crash | **Recover** (signal handler catches fault on dedicated WAMR thread, restarts host, notifies user) |
| Extension Host | Script timeout | **Kill** (fuel limit, notify user) |
| LSP Server | Crash | **Reconnect** (restart, re-send documents) |
| LSP Server | Bad response | **Degrade** (discard, show stale data) |
| Config | Parse error | **Degrade** (use defaults, show diagnostic) |
| File Watcher | Event flood | **Throttle** (100ms debounce) |
| File Watcher | iCloud conflict | **Prompt** (diff dialog) |
| Bundle Loader | Legacy plist bundle | **Prompt** (permission dialog) |
| Swap File | Disk full | **Warn** (status bar warning, never silent) |

---

## 14. Observability

All modules use `os_log` with subsystem `com.sw3.textfellow`:

| Category | Covers |
|----------|--------|
| TextEngine | Mutations, snapshots, operation log |
| Renderer | Frame timing, atlas ops, shaders |
| Syntax | Parser selection, fallback, timing |
| ExtensionHost | Boot, execution, IPC, crash/restart |
| LSP | Server lifecycle, request/response |
| Config | Layer resolution, parse errors, hot-reload |
| BundleLoader | Discovery, parsing, capability checks |
| FileWatcher | Events, throttling, conflicts |

---

## 15. Non-Negotiable Principles

1. **Never use `NSTextView` or `UITextView`** for the editor viewport
2. **Never bypass `TextStorage`** — no direct `BigString` access outside `SW3TTextEngine`
3. **Never hard-code platform assumptions** — `#if os(...)` only in adaptation layers
4. **50ms launch** — usable before extension host boots
5. **Every feature behind a protocol** — swappable implementations
6. **No HTML/CSS/Electron** — native rendering only
7. **Never break iOS support** — shared modules compile for both platforms always
8. **TextMate's soul, not VS Code's skin** — the default state is a clean canvas: text area, tab bar, gutter, status bar. Nothing else visible. Every modern feature follows progressive disclosure. The visual identity test: a screenshot of default TextFellow next to TextMate 2 should read "same but sharper," never "looks like VS Code."
9. **No feature imposes itself** — sidebar hidden by default, terminal hidden by default, all panels slide out completely. The `[ui]` section in settings lets users permanently enable features, but factory defaults are minimal.

---

## 16. Technology Stack

| Layer | Technology | Notes |
|-------|-----------|-------|
| Language | Swift 6 | Strict concurrency |
| Text engine | `BigString` (swift-collections) | Behind `TextStorage` protocol |
| Text layout | CoreText | All Unicode complexity |
| Rendering | Metal via `MTKView` | GPU glyph atlas |
| UI framework | SwiftUI | Everything except editor viewport |
| Syntax | tree-sitter + tmLanguage/Onigmo | Unified `SyntaxHighlighter` protocol |
| Bundle runtime | WAMR + ruby.wasm | Behind `ExtensionHostProtocol` |
| Terminal | SwiftTerm | Embedded panel |
| LSP | Built-in client | Full spec |
| Config | TOML + `.editorconfig` | Layered resolution |
| Undo | Persistent tree | COW snapshot sharing |
| File watching | FSEvents / DispatchSource | Respects exclusions |
| Distribution (macOS) | DMG + Sparkle + Homebrew | Per-arch, notarized |
| Distribution (iOS) | App Store | WASM = review compatible |

---

## 17. What Changed vs. Classic TextMate

| Aspect | Classic TextMate | SW³ TextFellow |
|--------|-----------------|----------------|
| Language | Objective-C++ | Swift 6 |
| Text engine | Custom AA-tree (C++) | BigString (Swift B-tree rope) |
| Rendering | CoreText + CGContext | CoreText + Metal GPU |
| UI | AppKit (48 frameworks) | SwiftUI + Metal |
| Syntax | Onigmo regex only | tree-sitter primary + Onigmo fallback |
| Bundle execution | Spawn Ruby subprocess | WASM sandbox (WAMR + ruby.wasm) |
| Undo | Linear | Persistent tree with branching |
| Config | Plist | Layered TOML + .editorconfig |
| Platform | macOS only | macOS + iPadOS |
| Build system | Custom Rave → Ninja | Xcode + SPM |
| LSP | None | Full LSP spec client |
| Terminal | None | Embedded (SwiftTerm) |
| Distribution | Manual DMG | Sparkle + App Store + Homebrew |
| Sandbox | None | App Sandbox + WASM capabilities |

---

*This document is updated continuously. Last updated: 2026-03-22.*
