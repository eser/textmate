// TextFellowInfo.swift — First Swift file in the TextFellow migration
//
// This demonstrates Swift/ObjC interop working in the TextFellow app.
// New utilities should be written in Swift. Existing ObjC++ code is
// accessed via the bridging header.

import Cocoa
import os.log

/// App metadata accessible from both Swift and ObjC.
@objc(SW3TAppInfo)
final class AppInfo: NSObject, @unchecked Sendable {
    @objc static let shared = AppInfo()

    @objc var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "TextFellow"
    }

    @objc var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0"
    }

    @objc var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    @objc var supportPath: String {
        let paths = NSSearchPathForDirectoriesInDomains(
            .applicationSupportDirectory, .userDomainMask, true)
        return (paths.first ?? "~/Library/Application Support") + "/TextMate"
    }

    @objc var cachePath: String {
        let paths = NSSearchPathForDirectoriesInDomains(
            .cachesDirectory, .userDomainMask, true)
        return (paths.first ?? "~/Library/Caches") + "/com.macromates.TextMate"
    }

    /// Initialize subsystems on first access.
    @objc func bootstrap() {
        let dbg = DebugLogger.shared
        dbg.log("BOOT", "TextFellow bootstrap starting")

        // Register defaults for TextFellow features
        UserDefaults.standard.register(defaults: [
            "metalOverlay": false,
            "metalRenderer": true, // Pipeline integration: Metal renders inside drawRect via offscreen texture + blit.
        ])
        dbg.log("BOOT", "metalRenderer=\(UserDefaults.standard.bool(forKey: "metalRenderer")), debugMode=\(dbg.isEnabled)")

        // Load user config (~/.config/sw3t/settings.toml)
        LayeredConfig.shared.loadUserSettings()
        dbg.log("BOOT", "LayeredConfig loaded")

        // Initialize grammar registry (triggers grammar loading)
        _ = GrammarRegistry.shared
        dbg.log("BOOT", "GrammarRegistry initialized: \(GrammarRegistry.shared.registeredCount) grammars")

        // Initialize LSP coordinator (listens for document open events)
        _ = LSPCoordinator.shared
        dbg.log("BOOT", "LSPCoordinator initialized")

        // Show boot toast after a short delay (window needs to exist)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            ToastManager.shared.show("TextFellow ready — \(GrammarRegistry.shared.registeredCount) grammars loaded", category: "INFO")
        }

        // Watch for document opens to apply EditorConfig
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(documentDidOpen(_:)),
            name: NSNotification.Name("OakDocumentDidOpenNotification"),
            object: nil
        )

        // Watch for grammar changes to run tree-sitter in parallel
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(bufferGrammarDidChange(_:)),
            name: NSNotification.Name("SW3TBufferGrammarDidChange"),
            object: nil
        )

        os_log(.info, "TextFellow bootstrapped: %{public}@ grammars, %{public}d LSP servers registered",
               GrammarRegistry.shared.availableLanguages.joined(separator: ", "),
               LSPCoordinator.shared.registeredServerCount)
    }

    @objc private func bufferGrammarDidChange(_ notification: Notification) {
        guard let ext = notification.userInfo?["extension"] as? String else { return }
        let hasTS = GrammarRegistry.shared.hasGrammar(forExtension: ext)
        if hasTS {
            os_log(.info, "tree-sitter grammar active for .%{public}@ (running alongside TextMate grammar)", ext)
            // Tree-sitter parse runs in parallel — tokens available via
            // GrammarRegistry.shared.highlighter(forExtension:)?.highlight()
            // The MetalFullRenderer can consume these for GPU-rendered syntax colors
        }
    }

    @objc private func documentDidOpen(_ notification: Notification) {
        guard let path = notification.userInfo?["path"] as? String else { return }

        // Apply .editorconfig for this file
        EditorConfig.applyToConfig(LayeredConfig.shared, forFile: path)

        // Apply tree-sitter grammar availability info
        let ext = (path as NSString).pathExtension
        if GrammarRegistry.shared.hasGrammar(forExtension: ext) {
            os_log(.debug, "tree-sitter grammar available for .%{public}@", ext)
        }

        // Record initial state in the branching undo tree
        undoTrees[path] = UndoTreeHandle()
    }

    // MARK: - Undo Tree (parallel to C++ undo_manager_t)

    /// Per-document undo trees — keyed by file path.
    /// These track state in parallel with the existing C++ undo system,
    /// ready for the undo tree navigator UI.
    private var undoTrees: [String: UndoTreeHandle] = [:]

    /// Record a document state change (called from ObjC++ bridge).
    @objc func recordUndoState(forPath path: String, text: String) {
        undoTrees[path]?.recordState(text: text)
    }

    /// Get the undo tree for a document.
    @objc func undoTree(forPath path: String) -> UndoTreeHandle? {
        undoTrees[path]
    }
}
