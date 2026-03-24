// SW³ TextFellow — LSP Settings View
// SPDX-License-Identifier: GPL-3.0-or-later
//
// SwiftUI view for configuring Language Server Protocol servers.
// This is a NEW feature that doesn't exist in TextMate, so SwiftUI is appropriate.

import SwiftUI

/// Configuration for a language server.
struct LSPServerConfig: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var command: String
    var arguments: String
    var languages: String // comma-separated
    var enabled: Bool

    init(name: String = "", command: String = "", arguments: String = "", languages: String = "", enabled: Bool = true) {
        self.id = UUID()
        self.name = name
        self.command = command
        self.arguments = arguments
        self.languages = languages
        self.enabled = enabled
    }
}

/// SwiftUI view for managing LSP server configurations.
/// Intended to be hosted in an NSHostingController within the existing
/// Preferences window, as an additional tab.
public struct LSPSettingsView: View {
    @State private var servers: [LSPServerConfig] = Self.defaultServers
    @State private var selectedServer: LSPServerConfig.ID?

    public var body: some View {
        HSplitView {
            // Server list
            List(selection: $selectedServer) {
                ForEach(servers) { server in
                    HStack {
                        Image(systemName: server.enabled ? "circle.fill" : "circle")
                            .foregroundStyle(server.enabled ? .green : .secondary)
                            .font(.caption)
                        VStack(alignment: .leading) {
                            Text(server.name)
                                .font(.body)
                            Text(server.languages)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(server.id)
                }
            }
            .frame(minWidth: 180)

            // Detail editor
            if let index = servers.firstIndex(where: { $0.id == selectedServer }) {
                Form {
                    TextField("Name:", text: $servers[index].name)
                    TextField("Command:", text: $servers[index].command)
                        .font(.system(.body, design: .monospaced))
                    TextField("Arguments:", text: $servers[index].arguments)
                        .font(.system(.body, design: .monospaced))
                    TextField("Languages:", text: $servers[index].languages)
                        .help("Comma-separated: swift, c, cpp")
                    Toggle("Enabled", isOn: $servers[index].enabled)
                }
                .padding()
                .frame(minWidth: 300)
            } else {
                Text("Select a language server")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 500, minHeight: 250)
    }

    private static let defaultServers: [LSPServerConfig] = [
        LSPServerConfig(name: "SourceKit-LSP",   command: "sourcekit-lsp",              languages: "swift, c, cpp, objc, objcpp"),
        LSPServerConfig(name: "TypeScript",       command: "typescript-language-server",  arguments: "--stdio", languages: "typescript, javascript, tsx, jsx, js, cjs, mjs"),
        LSPServerConfig(name: "Rust Analyzer",    command: "rust-analyzer",              languages: "rust"),
        LSPServerConfig(name: "Python (Pyright)", command: "pyright-langserver",          arguments: "--stdio", languages: "python"),
        LSPServerConfig(name: "Go (gopls)",       command: "gopls",                      arguments: "serve",   languages: "go"),
        LSPServerConfig(name: "Lua",              command: "lua-language-server",         languages: "lua"),
        LSPServerConfig(name: "Bash / Shell",     command: "bash-language-server",        arguments: "start",   languages: "sh, bash, zsh"),
        LSPServerConfig(name: "HTML",             command: "vscode-html-language-server", arguments: "--stdio", languages: "html, htm"),
        LSPServerConfig(name: "CSS",              command: "vscode-css-language-server",  arguments: "--stdio", languages: "css, scss, less"),
        LSPServerConfig(name: "JSON",             command: "vscode-json-language-server", arguments: "--stdio", languages: "json, jsonc"),
        LSPServerConfig(name: "YAML",             command: "yaml-language-server",        arguments: "--stdio", languages: "yaml, yml"),
        LSPServerConfig(name: "TOML (Taplo)",     command: "taplo",                      arguments: "lsp stdio", languages: "toml"),
        LSPServerConfig(name: "Markdown",         command: "marksman",                   arguments: "server",  languages: "md, markdown"),
        LSPServerConfig(name: "Ruby (Solargraph)",command: "solargraph",                  arguments: "stdio",   languages: "ruby, rake, gemspec"),
        LSPServerConfig(name: "PHP (Phpactor)",   command: "phpactor",                   arguments: "language-server", languages: "php"),
        LSPServerConfig(name: "Elixir",           command: "elixir-ls",                  languages: "elixir, ex, exs"),
        LSPServerConfig(name: "Zig",              command: "zls",                        languages: "zig"),
        LSPServerConfig(name: "Kotlin",           command: "kotlin-language-server",      languages: "kotlin, kt, kts"),
        LSPServerConfig(name: "Java (JDTLS)",     command: "jdtls",                      languages: "java"),
        LSPServerConfig(name: "C# (OmniSharp)",   command: "OmniSharp",                  arguments: "-lsp",    languages: "csharp, cs"),
        LSPServerConfig(name: "Terraform",        command: "terraform-ls",               arguments: "serve",   languages: "terraform, tf, tfvars"),
    ]
}

/// NSHostingController wrapper for embedding in the AppKit Preferences window.
@objc(SW3TLSPSettingsViewController)
final class LSPSettingsViewController: NSHostingController<LSPSettingsView> {
    @objc init() {
        super.init(rootView: LSPSettingsView())
    }

    @MainActor required init?(coder: NSCoder) {
        super.init(coder: coder, rootView: LSPSettingsView())
    }
}
