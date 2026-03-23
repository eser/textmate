# SW³ TextFellow — Pragmatic Migration Plan

> **Long name:** SW³ TextFellow | **Short name / app name:** TextFellow | **Code name:** sw3t | **License:** GPL-3.0

## Strategy: Strangler Fig Pattern

Keep TextMate running and looking identical. Replace internal components one at a time. Each step must produce a working app that is visually indistinguishable from the previous step. If a migration step changes the appearance, it's wrong.

```
Phase 0: TextMate works, looks like TextMate                    ✅ Done
Phase 1: TextMate works, looks like TextMate, builds with Xcode ✅ Done
Phase 2: TextMate works, looks like TextMate, fewer C++ deps    ✅ Done
Phase 3: TextMate works, looks like TextMate, some Swift modules ✅ Done
Phase 4: TextMate works, looks like TextMate, tree-sitter added  ✅ Done
Phase 5: TextMate works, looks like TextMate, new features added ✅ Done
Phase 6: TextMate works, WASM extension system added             ✅ Done
Phase 7: TextMate works, SwiftUI for new features only           ✅ Done
Phase 8: iOS/iPadOS app target compiles                          ✅ Done
Phase 2: TextMate works, looks like TextMate, fewer C++ deps
Phase 3: TextMate works, looks like TextMate, some Swift modules
Phase 4: TextMate works, looks like TextMate, tree-sitter added
Phase 5: TextMate works, looks like TextMate, new features added
...
Phase N: SW³ TextFellow, looks like TextMate, all goals achieved
```

## Lessons Learned

1. **The greenfield SwiftUI rewrite failed.** SwiftUI cannot produce the pixel-perfect native AppKit look that TextMate has. Building from scratch and trying to approximate the UI was a mistake.
2. **Start from the working TextMate.** It already looks perfect. Evolve it gradually.
3. **AppKit for existing UI, SwiftUI only for genuinely new surfaces.** Don't replace working AppKit with SwiftUI approximations.
4. The abandoned greenfield Swift modules (`Sources/SW3T*`) are kept as design reference — the target abstractions (`TextStorage`, `SyntaxHighlighter`, `ExtensionHostProtocol`) are still the destination.

---

## Phase 0 — Baseline ✅

**Goal**: TextMate builds, runs, and looks correct.

- ✅ `./configure && ninja TextMate` builds successfully
- ✅ `local.rave` configured for Apple Silicon Homebrew (`/opt/homebrew`)
- ✅ Ad-hoc signed builds launch (`xattr -cr`)

## Phase 1 — Xcode Project + Dependency Cleanup ✅

**Goal**: Create an Xcode project that builds the same app. Eliminate external C++ dependencies. Modernize deployment target.

- ✅ Xcode project via XcodeGen (`project.yml` → `.xcodeproj`)
- ✅ `TextFellowCore` static library containing all 48 framework sources
- ✅ `TextFellow` app target linking the static library
- ✅ Secondary targets: `fellow` (CLI), `sw3t-query`, `PrivilegedTool`
- ✅ macOS 15.0 deployment target (from 10.12)
- ✅ Boost eliminated (`boost::crc` → zlib, `boost::variant` → `std::variant`, 51 files)
- ✅ Sparsehash eliminated (`dense_hash_map` → `std::unordered_map`)
- ✅ GitHub Actions CI running both Rave and Xcode builds
- ✅ Developer experience: `make build`, `make xcode-build`, `make check-deps`, `make verify`
- ✅ Rave build system kept alongside — both produce working apps

## Phase 2 — Eliminate Remaining External Dependencies ✅

**Goal**: Remove Cap'n Proto and libcurl. Keep the app identical.

- ✅ Cap'n Proto → plist serialization (fs_cache already had plist path, encoding uses plist dictionaries)
- ✅ libcurl → `NSURLSession` with streaming delegate (download.mm, download_tbz.mm)
- ✅ Both builds pass, zero external C/C++ library dependencies remain

## Phase 3 — Introduce Swift at the Edges ✅

**Goal**: Start writing new code in Swift. Keep existing ObjC++ working.

- ✅ Swift 6 enabled with C++ interop (`SWIFT_OBJC_INTEROP_MODE: objcxx`)
- ✅ ObjC bridging header (`Xcode/TextFellow-Bridging-Header.h`)
- ✅ First Swift file: `TextFellowInfo.swift` — `AppInfo` class with `@objc` bridging
- ✅ Swift Testing target: `TextFellowTests` with 4 passing tests
- ✅ No existing `.mm` file touched for Swift integration

## Phase 4 — Add tree-sitter Alongside TextMate Grammars ✅

**Goal**: tree-sitter as an additional syntax engine. TextMate grammars still work.

- ✅ tree-sitter C runtime added as git submodule + static library target
- ✅ `SyntaxHighlighter` protocol in Swift (`Frameworks/SW3TSyntax/`)
- ✅ `TreeSitterHighlighter` implementation calling tree-sitter C API via bridging header
- ✅ `PlainTextHighlighter` as no-op fallback
- ✅ Existing TextMate grammar engine untouched — remains the default

## Phase 5 — New Features (Keeping Existing UI) ✅

**Goal**: Command palette, LSP, TOML config — added on top of existing AppKit UI.

- ✅ Command palette: `SW3TCommandPalette` — AppKit NSPanel with fuzzy search, `@objc` bridge
- ✅ LSP client: `SW3TLSP` — async/await actor, JSON-RPC 2.0, Process+Pipe subprocess
- ✅ TOML config: `SW3TConfig` — layered resolution (defaults→user→project→directory), minimal TOML parser
- `.editorconfig` support (deferred — TOML config layer handles the pattern)

**Rule**: Every new UI element uses AppKit to match the existing look.

## Phase 6 — WASM Extension System ✅

**Goal**: Add WAMR + ruby.wasm as an alternative bundle execution path.

- ✅ WAMR added as git submodule (`vendor/wamr`)
- ✅ `ExtensionRunner` protocol with two implementations:
  - `SubprocessExtensionRunner` — existing fork/exec behavior (default)
  - `WASMExtensionRunner` — WASM execution via WAMR (stub, runtime not yet compiled)
- ✅ `ExtensionHost` singleton routes commands to appropriate runner
- ✅ Existing Ruby subprocess execution unchanged — used as fallback

## Phase 7 — Gradual UI Modernization ✅

**Goal**: Only add SwiftUI for NEW features that don't exist in TextMate.

- ✅ `LSPSettingsView` — SwiftUI view for LSP server configuration (new feature)
- ✅ `LSPSettingsViewController` — NSHostingController wrapper for AppKit integration
- Metal rendering deferred (existing CoreText+CGContext works fine)

**Rule**: Existing AppKit UI untouched. SwiftUI only for genuinely new surfaces.

## Phase 8 — iOS/iPadOS ✅

**Goal**: Cross-platform via shared Swift modules.

- ✅ `TextFellowiOS` target: SwiftUI DocumentGroup app for iPhone/iPad
- ✅ Builds for iOS Simulator (arm64)
- ✅ Swift modules from Phases 3-6 are cross-platform by design
- iOS UI is entirely SwiftUI — no AppKit to port
- C++ core and Onigmo compile for iOS
- First time SwiftUI is primary UI — no TextMate iOS app to match

---

## Principles

1. **The app must look identical at every step.** If a change makes it look different, revert.
2. **Migrate internals, not externals.** The user sees the same app. The code inside changes.
3. **One thing at a time.** Each PR changes one component.
4. **Keep the old path working.** New code runs alongside old code until proven.
5. **AppKit for existing UI, SwiftUI for new UI.**
6. **The destination is the same.** Everything in SPEC.md is still the goal. The path is different.

## What Stays from the Vision

All architecture decisions in SPEC.md remain valid as the target destination:
- `TextStorage` protocol, `SyntaxHighlighter` protocol, `ExtensionHostProtocol`
- BigString as eventual text engine (behind protocol)
- tree-sitter + TextMate grammar dual engine
- WASM bundle execution
- LSP client
- Cross-platform (macOS + iPadOS)
- SW³ TextFellow branding, GPL-3.0

## What Changed from the Original Plan

- **No greenfield rewrite.** Evolve the existing codebase.
- **AppKit first, SwiftUI when appropriate.** Not SwiftUI-first.
- **Metal only when proven necessary.** Existing rendering may be fine.
- **Incremental, not big-bang.** Each step is a small, safe, reversible change.

---

*Historical reference: see PLAN_OLD.md (original greenfield plan) and SPEC_OLD.md (original spec). These files are preserved forever.*
