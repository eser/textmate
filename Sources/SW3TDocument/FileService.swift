// SW³ TextFellow — File Service
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Reads a directory tree and produces a FileNode hierarchy.
///
/// Respects smart indexing exclusions (node_modules, .git, build, etc.)
/// as defined in the SPEC.
public struct FileService: Sendable {
    /// Directories excluded from indexing by default.
    /// User-configurable via [indexing] in settings.toml.
    public static let defaultExclusions: Set<String> = [
        "node_modules", ".git", "build", "dist", ".next",
        "__pycache__", ".cache", "target", "Pods", ".build",
        "DerivedData", ".DS_Store",
    ]

    private let exclusions: Set<String>

    public init(exclusions: Set<String> = FileService.defaultExclusions) {
        self.exclusions = exclusions
    }

    /// Scan a directory and return a sorted file tree.
    /// Directories first (sorted), then files (sorted).
    public func scanDirectory(at url: URL) throws -> [FileTreeNode] {
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
            options: [.skipsPackageDescendants]
        )

        var directories: [FileTreeNode] = []
        var files: [FileTreeNode] = []

        for itemURL in contents {
            let name = itemURL.lastPathComponent

            // Skip excluded directories and hidden files
            if exclusions.contains(name) { continue }
            if name.hasPrefix(".") && name != ".sw3t" && name != ".editorconfig" { continue }

            let resourceValues = try itemURL.resourceValues(forKeys: [.isDirectoryKey])
            let isDirectory = resourceValues.isDirectory ?? false

            if isDirectory {
                let children = (try? scanDirectory(at: itemURL)) ?? []
                directories.append(FileTreeNode(
                    name: name,
                    url: itemURL,
                    isDirectory: true,
                    children: children
                ))
            } else {
                files.append(FileTreeNode(
                    name: name,
                    url: itemURL,
                    isDirectory: false,
                    children: []
                ))
            }
        }

        // TextMate convention: directories first (sorted), then files (sorted)
        directories.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        files.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        return directories + files
    }

    /// Read a file's content as a String.
    public func readFile(at url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    /// Write a String to a file.
    public func writeFile(_ content: String, to url: URL) throws {
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}

/// A node in the scanned file tree (with URL for I/O).
public struct FileTreeNode: Sendable {
    public let name: String
    public let url: URL
    public let isDirectory: Bool
    public let children: [FileTreeNode]

    public init(name: String, url: URL, isDirectory: Bool, children: [FileTreeNode]) {
        self.name = name
        self.url = url
        self.isDirectory = isDirectory
        self.children = children
    }
}
