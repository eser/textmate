// SW³ TextFellow — Configuration Provider Protocol
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Every feature behind a protocol — ConfigProvider is the single
// interface for accessing resolved configuration values.
//
// Resolution order (later overrides earlier):
//   1. Built-in defaults (hardcoded)
//   2. User settings:    ~/.config/sw3t/settings.toml
//   3. .editorconfig:    per-file via globs
//   4. Project settings: .sw3t/settings.toml at project root
//   5. File-type:        [filetype.rust] sections
//   6. Directory-local:  .sw3t/settings.toml in subdirectories

import Foundation

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
