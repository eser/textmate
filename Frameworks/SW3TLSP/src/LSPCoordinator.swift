// SW³ TextFellow — LSP Coordinator
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Watches for document open/close events and manages LSP server lifecycles.
// Auto-launches the appropriate language server based on file extension.

import Foundation
import os.log

/// Manages LSP server instances per language.
@objc(SW3TLSPCoordinator)
public final class LSPCoordinator: NSObject, @unchecked Sendable {
    @objc public static let shared = LSPCoordinator()

    /// Active LSP clients, keyed by language identifier.
    private var clients: [String: LSPClient] = [:]

    /// Server configurations: extension → (language, command, args)
    private var serverConfigs: [String: ServerConfig] = [:]

    struct ServerConfig {
        let language: String
        let command: String
        let arguments: [String]
    }

    public override init() {
        super.init()
        registerDefaultServers()

        // Watch for document open notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(documentDidOpen(_:)),
            name: NSNotification.Name("OakDocumentDidOpenNotification"),
            object: nil
        )
    }

    // MARK: - Server Registration

    /// Register a language server for given file extensions.
    @objc public func registerServer(
        language: String,
        command: String,
        arguments: [String],
        extensions: [String]
    ) {
        let config = ServerConfig(language: language, command: command, arguments: arguments)
        for ext in extensions {
            serverConfigs[ext.lowercased()] = config
        }
    }

    private func registerDefaultServers() {
        // SourceKit-LSP (Swift, C, C++, ObjC)
        registerServer(
            language: "swift",
            command: "sourcekit-lsp",
            arguments: [],
            extensions: ["swift", "c", "h", "cc", "cpp", "m", "mm"]
        )

        // TypeScript Language Server
        registerServer(
            language: "typescript",
            command: "typescript-language-server",
            arguments: ["--stdio"],
            extensions: ["ts", "tsx", "js", "jsx", "mjs", "cjs"]
        )

        // Rust Analyzer
        registerServer(
            language: "rust",
            command: "rust-analyzer",
            arguments: [],
            extensions: ["rs"]
        )

        // Python (Pyright)
        registerServer(
            language: "python",
            command: "pyright-langserver",
            arguments: ["--stdio"],
            extensions: ["py", "pyw"]
        )

        // Go (gopls)
        registerServer(
            language: "go",
            command: "gopls",
            arguments: ["serve"],
            extensions: ["go"]
        )

        // Lua
        registerServer(
            language: "lua",
            command: "lua-language-server",
            arguments: [],
            extensions: ["lua"]
        )

        // Bash / Shell
        registerServer(
            language: "shellscript",
            command: "bash-language-server",
            arguments: ["start"],
            extensions: ["sh", "bash", "zsh"]
        )

        // HTML
        registerServer(
            language: "html",
            command: "vscode-html-language-server",
            arguments: ["--stdio"],
            extensions: ["html", "htm"]
        )

        // CSS / SCSS / Less
        registerServer(
            language: "css",
            command: "vscode-css-language-server",
            arguments: ["--stdio"],
            extensions: ["css", "scss", "less"]
        )

        // JSON
        registerServer(
            language: "json",
            command: "vscode-json-language-server",
            arguments: ["--stdio"],
            extensions: ["json", "jsonc"]
        )

        // YAML
        registerServer(
            language: "yaml",
            command: "yaml-language-server",
            arguments: ["--stdio"],
            extensions: ["yaml", "yml"]
        )

        // TOML
        registerServer(
            language: "toml",
            command: "taplo",
            arguments: ["lsp", "stdio"],
            extensions: ["toml"]
        )

        // Markdown
        registerServer(
            language: "markdown",
            command: "marksman",
            arguments: ["server"],
            extensions: ["md", "markdown"]
        )

        // Ruby
        registerServer(
            language: "ruby",
            command: "solargraph",
            arguments: ["stdio"],
            extensions: ["rb", "rake", "gemspec"]
        )

        // PHP
        registerServer(
            language: "php",
            command: "phpactor",
            arguments: ["language-server"],
            extensions: ["php"]
        )

        // Elixir
        registerServer(
            language: "elixir",
            command: "elixir-ls",
            arguments: [],
            extensions: ["ex", "exs"]
        )

        // Zig
        registerServer(
            language: "zig",
            command: "zls",
            arguments: [],
            extensions: ["zig"]
        )

        // Kotlin
        registerServer(
            language: "kotlin",
            command: "kotlin-language-server",
            arguments: [],
            extensions: ["kt", "kts"]
        )

        // Java
        registerServer(
            language: "java",
            command: "jdtls",
            arguments: [],
            extensions: ["java"]
        )

        // C#
        registerServer(
            language: "csharp",
            command: "OmniSharp",
            arguments: ["-lsp"],
            extensions: ["cs"]
        )

        // Terraform
        registerServer(
            language: "terraform",
            command: "terraform-ls",
            arguments: ["serve"],
            extensions: ["tf", "tfvars"]
        )
    }

    // MARK: - Document Events

    @objc private func documentDidOpen(_ notification: Notification) {
        guard let path = notification.userInfo?["path"] as? String else { return }

        let ext = (path as NSString).pathExtension.lowercased()
        guard let config = serverConfigs[ext] else { return }

        // Already running for this language?
        if clients[config.language] != nil { return }

        // Check if the server binary exists
        guard isCommandAvailable(config.command) else {
            os_log(.info, "LSP server '%{public}s' not found, skipping", config.command)
            return
        }

        // Launch server
        Task {
            do {
                let client = LSPClient(
                    serverPath: config.command,
                    arguments: config.arguments
                )
                try await client.start()
                clients[config.language] = client
                os_log(.info, "LSP server started: %{public}s for %{public}s",
                       config.command, config.language)
            } catch {
                os_log(.error, "LSP server failed to start: %{public}s — %{public}s",
                       config.command, error.localizedDescription)
            }
        }
    }

    // MARK: - Public API

    /// Get the active LSP client for a file, if any.
    public func client(forFileExtension ext: String) -> LSPClient? {
        guard let config = serverConfigs[ext.lowercased()] else { return nil }
        return clients[config.language]
    }

    /// Registered language server count.
    @objc public var registeredServerCount: Int {
        Set(serverConfigs.values.map(\.language)).count
    }

    /// Active (running) server count.
    @objc public var activeServerCount: Int {
        clients.count
    }

    // MARK: - Helpers

    private func isCommandAvailable(_ command: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [command]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func findProjectRoot(from filePath: String) -> String {
        var dir = (filePath as NSString).deletingLastPathComponent
        while dir != "/" {
            // Look for common project root indicators
            for marker in [".git", "Package.swift", "Cargo.toml", "package.json", "go.mod", ".sw3t"] {
                if FileManager.default.fileExists(atPath: (dir as NSString).appendingPathComponent(marker)) {
                    return dir
                }
            }
            dir = (dir as NSString).deletingLastPathComponent
        }
        return (filePath as NSString).deletingLastPathComponent
    }
}
