// SW³ TextFellow — EditorConfig Support
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Parses .editorconfig files per the EditorConfig spec (editorconfig.org).
// Integrates with LayeredConfig as a config layer at priority 3.

import Foundation

/// Parser for .editorconfig files.
/// Maps EditorConfig keys to SW3T config keys.
@objc(SW3TEditorConfig)
public final class EditorConfig: NSObject, @unchecked Sendable {

    /// Parse .editorconfig files from the given file path up to root.
    /// Returns a flat dictionary of resolved config values for that file.
    public static func resolve(forFile filePath: String) -> [String: ConfigValue] {
        let url = URL(fileURLWithPath: filePath)
        var configs: [([Section], Bool)] = [] // (sections, isRoot)

        // Walk up directory tree collecting .editorconfig files
        var dir = url.deletingLastPathComponent()
        while true {
            let ecPath = dir.appendingPathComponent(".editorconfig")
            if FileManager.default.fileExists(atPath: ecPath.path) {
                let (sections, isRoot) = parseFile(at: ecPath)
                configs.append((sections, isRoot))
                if isRoot { break }
            }

            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { break } // reached filesystem root
            dir = parent
        }

        // Apply in reverse order (closest .editorconfig wins)
        let filename = url.lastPathComponent
        var result: [String: ConfigValue] = [:]
        for (sections, _) in configs.reversed() {
            for section in sections {
                if matches(pattern: section.pattern, filename: filename) {
                    for (key, value) in section.properties {
                        if let mapped = mapToSW3TKey(key) {
                            result[mapped] = convertValue(key: key, value: value)
                        }
                    }
                }
            }
        }

        return result
    }

    /// Load .editorconfig for a file and add as a config layer.
    @objc public static func applyToConfig(_ config: LayeredConfig, forFile filePath: String) {
        let values = resolve(forFile: filePath)
        if !values.isEmpty {
            config.addLayer(ConfigLayer(name: "editorconfig", values: values, priority: 3))
        }
    }

    // MARK: - Parsing

    struct Section {
        let pattern: String
        var properties: [(String, String)]
    }

    static func parseFile(at url: URL) -> (sections: [Section], isRoot: Bool) {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return ([], false)
        }

        var sections: [Section] = []
        var currentSection: Section?
        var isRoot = false

        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines and comments
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix(";") {
                continue
            }

            // Section header: [pattern]
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                if let section = currentSection {
                    sections.append(section)
                }
                let pattern = String(trimmed.dropFirst().dropLast())
                    .trimmingCharacters(in: .whitespaces)
                currentSection = Section(pattern: pattern, properties: [])
                continue
            }

            // Key = value (before any section = root properties)
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }

            let key = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            let value = parts[1].trimmingCharacters(in: .whitespaces)

            if currentSection != nil {
                currentSection?.properties.append((key, value))
            } else if key == "root" && value.lowercased() == "true" {
                isRoot = true
            }
        }

        if let section = currentSection {
            sections.append(section)
        }

        return (sections, isRoot)
    }

    // MARK: - Pattern Matching

    /// Simple glob matching for EditorConfig patterns.
    static func matches(pattern: String, filename: String) -> Bool {
        if pattern == "*" { return true }

        // Brace expansion: *.{js,ts} (check before simple extension)
        if pattern.hasPrefix("*.{") && pattern.hasSuffix("}") {
            let inner = pattern[pattern.index(pattern.startIndex, offsetBy: 3)..<pattern.index(before: pattern.endIndex)]
            let exts = inner.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            return exts.contains { filename.hasSuffix(".\($0)") }
        }

        // Extension match: *.ext
        if pattern.hasPrefix("*.") {
            let ext = String(pattern.dropFirst(2))
            return filename.hasSuffix(".\(ext)")
        }

        // Exact match
        if pattern == filename { return true }

        // Bracket match: [Mm]akefile
        // Simplified: treat as exact match for now
        return false
    }

    // MARK: - Key Mapping

    /// Map EditorConfig key → SW3T config key.
    static func mapToSW3TKey(_ ecKey: String) -> String? {
        switch ecKey {
        case "indent_size":     return "editor.tab_size"
        case "tab_width":       return "editor.tab_size"
        case "indent_style":    return "editor.soft_tabs"
        case "end_of_line":     return "editor.line_ending"
        case "charset":         return "editor.encoding"
        case "trim_trailing_whitespace": return "editor.trim_trailing_whitespace"
        case "insert_final_newline":     return "editor.insert_final_newline"
        default:                return nil
        }
    }

    /// Convert EditorConfig value to ConfigValue with proper type.
    static func convertValue(key: String, value: String) -> ConfigValue {
        switch key {
        case "indent_style":
            return .bool(value.lowercased() == "space")
        case "indent_size", "tab_width":
            return .integer(Int(value) ?? 4)
        case "trim_trailing_whitespace", "insert_final_newline":
            return .bool(value.lowercased() == "true")
        case "end_of_line":
            switch value.lowercased() {
            case "lf":   return .string("LF")
            case "crlf": return .string("CRLF")
            case "cr":   return .string("CR")
            default:     return .string(value)
            }
        default:
            return .string(value)
        }
    }
}
