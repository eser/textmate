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
        // Register defaults for TextFellow features
        UserDefaults.standard.register(defaults: [
            "metalOverlay": true,
            "metalRenderer": true,
        ])

        // Load user config (~/.config/sw3t/settings.toml)
        LayeredConfig.shared.loadUserSettings()

        // Initialize grammar registry (triggers grammar loading)
        _ = GrammarRegistry.shared

        // Initialize LSP coordinator (listens for document open events)
        _ = LSPCoordinator.shared

        // Watch for document opens to apply EditorConfig
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(documentDidOpen(_:)),
            name: NSNotification.Name("OakDocumentDidOpenNotification"),
            object: nil
        )

        os_log(.info, "TextFellow bootstrapped: %{public}@ grammars, %{public}d LSP servers registered",
               GrammarRegistry.shared.availableLanguages.joined(separator: ", "),
               LSPCoordinator.shared.registeredServerCount)
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
    }
}
