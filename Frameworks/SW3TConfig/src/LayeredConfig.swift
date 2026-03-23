// SW3 TextFellow — Layered Configuration (Framework Edition)
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Self-contained layered configuration with TOML parsing.
// Adapted from Sources/SW3TConfig/ for integration into the
// TextMate Frameworks directory alongside existing ObjC++ code.
//
// @objc accessible so existing Objective-C++ settings code
// can read resolved values.

import Foundation

// MARK: - Protocol

/// Protocol for accessing resolved configuration.
public protocol ConfigProvider: Sendable {
    /// Get a string value for a key path (e.g., "theme.editor").
    func string(for keyPath: String) -> String?

    /// Get an integer value.
    func integer(for keyPath: String) -> Int?

    /// Get a boolean value.
    func bool(for keyPath: String) -> Bool?

    /// Get a resolved value for a file at a specific path.
    /// This applies directory-local and file-type overrides.
    func string(for keyPath: String, fileAt path: URL) -> String?

    /// All keys in a section (e.g., "ui" returns all ui.* keys).
    func keys(in section: String) -> [String]
}

// MARK: - Value Type

/// Configuration value types.
public enum ConfigValue: Sendable, Equatable {
    case string(String)
    case integer(Int)
    case bool(Bool)
    case array([String])

    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    public var intValue: Int? {
        if case .integer(let i) = self { return i }
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }
}

// MARK: - Layer

/// A single configuration layer (one TOML file or built-in defaults).
public struct ConfigLayer: Sendable {
    public let name: String
    public let values: [String: ConfigValue]
    public let priority: Int // higher = overrides lower

    public init(name: String, values: [String: ConfigValue], priority: Int) {
        self.name = name
        self.values = values
        self.priority = priority
    }
}

// MARK: - Layered Config

/// Layered configuration that resolves values from multiple sources.
///
/// ```
///  Resolution (higher priority wins):
///
///  +-----------------------+  priority 6
///  | Directory-local .sw3t |
///  +-----------------------+  priority 5
///  | [filetype.X] section  |
///  +-----------------------+  priority 4
///  | Project .sw3t/        |
///  +-----------------------+  priority 3
///  | .editorconfig         |
///  +-----------------------+  priority 2
///  | User settings         |
///  +-----------------------+  priority 1
///  | Built-in defaults     |
///  +-----------------------+
/// ```
@objc public final class LayeredConfig: NSObject, ConfigProvider, @unchecked Sendable {

    @objc public static let shared = LayeredConfig()

    private var layers: [ConfigLayer] = []

    @objc public override init() {
        super.init()
        loadDefaults()
    }

    // MARK: - Layer Management

    /// Add a configuration layer.
    public func addLayer(_ layer: ConfigLayer) {
        layers.append(layer)
        layers.sort { $0.priority < $1.priority }
    }

    /// Load user settings from ~/.config/sw3t/settings.toml.
    @objc public func loadUserSettings() {
        let userConfigURL = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".config/sw3t/settings.toml")

        if let values = parseTOMLFile(at: userConfigURL) {
            addLayer(ConfigLayer(name: "user", values: values, priority: 2))
        }
    }

    /// Load project settings from .sw3t/settings.toml relative to project root.
    @objc public func loadProjectSettings(atPath path: String) {
        let projectRoot = URL(fileURLWithPath: path)
        let projectConfigURL = projectRoot.appendingPathComponent(".sw3t/settings.toml")
        if let values = parseTOMLFile(at: projectConfigURL) {
            addLayer(ConfigLayer(name: "project", values: values, priority: 4))
        }
    }

    /// Load from a TOML string with a given layer name and priority.
    public func loadTOMLString(_ content: String, name: String, priority: Int) {
        let values = parseTOML(content)
        addLayer(ConfigLayer(name: name, values: values, priority: priority))
    }

    // MARK: - ConfigProvider

    public func string(for keyPath: String) -> String? {
        resolvedValue(for: keyPath)?.stringValue
    }

    public func integer(for keyPath: String) -> Int? {
        resolvedValue(for: keyPath)?.intValue
    }

    public func bool(for keyPath: String) -> Bool? {
        resolvedValue(for: keyPath)?.boolValue
    }

    public func string(for keyPath: String, fileAt path: URL) -> String? {
        // TODO: Apply file-type and directory-local overrides
        string(for: keyPath)
    }

    public func keys(in section: String) -> [String] {
        let prefix = section + "."
        var allKeys: Set<String> = []
        for layer in layers {
            for key in layer.values.keys where key.hasPrefix(prefix) {
                allKeys.insert(key)
            }
        }
        return Array(allKeys).sorted()
    }

    // MARK: - ObjC Bridge

    /// Get a string value (ObjC-accessible).
    @objc public func stringValue(forKey key: String) -> String? {
        string(for: key)
    }

    /// Get an integer value (ObjC-accessible, returns -1 if missing).
    @objc public func integerValue(forKey key: String) -> Int {
        integer(for: key) ?? -1
    }

    /// Get a boolean value (ObjC-accessible).
    @objc public func boolValue(forKey key: String) -> Bool {
        bool(for: key) ?? false
    }

    /// Get all layers (for debugging).
    @objc public var layerCount: Int {
        layers.count
    }

    // MARK: - Resolution

    /// Resolve a value across all layers (highest priority wins).
    private func resolvedValue(for keyPath: String) -> ConfigValue? {
        for layer in layers.reversed() {
            if let value = layer.values[keyPath] {
                return value
            }
        }
        return nil
    }

    // MARK: - Built-in Defaults

    /// Factory defaults — TextMate's soul, progressive disclosure.
    private func loadDefaults() {
        let defaults: [String: ConfigValue] = [
            // UI — progressive disclosure defaults
            "ui.sidebar": .bool(false),
            "ui.terminal": .bool(false),
            "ui.scope_bar": .bool(false),
            "ui.minimap": .bool(false),
            "ui.line_numbers": .bool(true),
            "ui.fold_markers": .bool(true),
            "ui.git_gutter": .string("auto"),
            "ui.sticky_scroll": .bool(true),
            "ui.sticky_scroll_max_lines": .integer(3),
            "ui.typewriter_mode": .bool(false),

            // Editor
            "editor.font_name": .string("Menlo"),
            "editor.font_size": .integer(13),
            "editor.tab_size": .integer(4),
            "editor.soft_tabs": .bool(true),
            "editor.word_wrap": .bool(false),
            "editor.encoding": .string("UTF-8"),
            "editor.line_ending": .string("LF"),

            // Theme — independent chrome/editor
            "theme.editor": .string("Monokai"),
            "theme.chrome": .string("system"),

            // Syntax
            "syntax.incremental_mode": .string("debounced"),
            "syntax.debounce_ms": .integer(50),
            "syntax.parser_timeout_s": .integer(2),

            // Diagnostics
            "diagnostics.inline_summary": .bool(false),

            // Git
            "git.inline_blame": .bool(false),

            // Indexing
            "indexing.exclude": .array([
                "node_modules", ".git", "build", "dist", ".next",
                "__pycache__", ".cache", "target", "Pods", ".build",
            ]),

            // Gutter
            "gutter.relative_numbers": .bool(false),

            // Animations
            "animations.enabled": .bool(true),
            "animations.max_duration_ms": .integer(200),
        ]

        addLayer(ConfigLayer(name: "defaults", values: defaults, priority: 1))
    }

    // MARK: - TOML Parsing (minimal)

    /// Minimal TOML parser — handles key = "value", key = 42, key = true.
    private func parseTOMLFile(at url: URL) -> [String: ConfigValue]? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        return parseTOML(content)
    }

    /// Parse TOML content into a flat key-value map.
    /// Sections become key prefixes: [theme] editor = "X" -> "theme.editor" = "X"
    func parseTOML(_ content: String) -> [String: ConfigValue] {
        var result: [String: ConfigValue] = [:]
        var currentSection = ""

        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines and comments
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            // Section header: [section]
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                currentSection = String(trimmed.dropFirst().dropLast())
                    .trimmingCharacters(in: .whitespaces)
                continue
            }

            // Key = value
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }

            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let rawValue = parts[1].trimmingCharacters(in: .whitespaces)

            let fullKey = currentSection.isEmpty ? key : "\(currentSection).\(key)"

            // Parse value type
            if rawValue == "true" {
                result[fullKey] = .bool(true)
            } else if rawValue == "false" {
                result[fullKey] = .bool(false)
            } else if let intVal = Int(rawValue) {
                result[fullKey] = .integer(intVal)
            } else if rawValue.hasPrefix("\"") && rawValue.hasSuffix("\"") {
                let strVal = String(rawValue.dropFirst().dropLast())
                result[fullKey] = .string(strVal)
            } else if rawValue.hasPrefix("[") && rawValue.hasSuffix("]") {
                // Simple array parsing: ["a", "b", "c"]
                let inner = String(rawValue.dropFirst().dropLast())
                let elements = inner.components(separatedBy: ",").compactMap { element -> String? in
                    let trimmedEl = element.trimmingCharacters(in: .whitespaces)
                    if trimmedEl.hasPrefix("\"") && trimmedEl.hasSuffix("\"") {
                        return String(trimmedEl.dropFirst().dropLast())
                    }
                    return trimmedEl.isEmpty ? nil : trimmedEl
                }
                result[fullKey] = .array(elements)
            } else {
                result[fullKey] = .string(rawValue)
            }
        }

        return result
    }
}
