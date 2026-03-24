// SW³ TextFellow — Git Diff Gutter Engine
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Runs `git diff` on the current file and parses unified diff output
// into line-level change hunks for gutter rendering.
//
// Colors: NSColor.systemGreen (added), NSColor.systemRed (deleted),
//         NSColor.systemBlue (modified). Never hardcode hex values.

import AppKit
import os.log

// MARK: - Gutter Change Types

/// Type of change for a line in the gutter.
@objc public enum GitGutterChangeType: Int, Sendable {
    case added = 0
    case deleted = 1
    case modified = 2
}

/// A range of lines with a specific change type.
@objc public class GitGutterHunk: NSObject, @unchecked Sendable {
    @objc public let startLine: Int   // 0-based
    @objc public let lineCount: Int
    @objc public let changeType: GitGutterChangeType

    public init(startLine: Int, lineCount: Int, changeType: GitGutterChangeType) {
        self.startLine = startLine
        self.lineCount = lineCount
        self.changeType = changeType
    }

    /// Color for this hunk type (system-adaptive, never hardcoded).
    @objc public var color: NSColor {
        switch changeType {
        case .added:    return .systemGreen
        case .deleted:  return .systemRed
        case .modified: return .systemBlue
        }
    }
}

// MARK: - Git Diff Engine

@objc(SW3TGitDiffEngine)
public class GitDiffEngine: NSObject, @unchecked Sendable {

    /// Compute git diff hunks for a file. Returns empty array if not a git repo
    /// or git is not installed. Runs asynchronously to avoid blocking main thread.
    @objc public static func computeHunks(
        forFileAt path: String,
        completion: @escaping ([GitGutterHunk]) -> Void
    ) {
        DispatchQueue.global(qos: .utility).async {
            let hunks = Self.computeHunksSync(forFileAt: path)
            DispatchQueue.main.async {
                completion(hunks)
            }
        }
    }

    /// Synchronous version — call from background thread only.
    public static func computeHunksSync(forFileAt path: String) -> [GitGutterHunk] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["diff", "--unified=0", "--no-color", "--", path]

        // Run from the file's directory to find the git repo
        let fileURL = URL(fileURLWithPath: path)
        process.currentDirectoryURL = fileURL.deletingLastPathComponent()

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe() // silence stderr

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            os_log(.debug, "GitDiffEngine: git not available: %{public}@", error.localizedDescription)
            return []
        }

        guard process.terminationStatus == 0 || process.terminationStatus == 1 else {
            return [] // Not a git repo or binary file
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        return parseUnifiedDiff(output)
    }

    /// Parse unified diff output into GitGutterHunk array.
    static func parseUnifiedDiff(_ diff: String) -> [GitGutterHunk] {
        var hunks: [GitGutterHunk] = []

        // Match @@ -oldStart[,oldCount] +newStart[,newCount] @@
        let hunkPattern = #/@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/#
        for line in diff.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = String(line)
            guard s.hasPrefix("@@") else { continue }

            // Manual parsing since Regex requires iOS 16+
            guard let atRange = s.range(of: "@@ "),
                  let endAt = s.range(of: " @@", range: atRange.upperBound..<s.endIndex) else { continue }

            let header = s[atRange.upperBound..<endAt.lowerBound]
            let parts = header.split(separator: " ")
            guard parts.count >= 2 else { continue }

            // Parse +newStart,newCount
            let newPart = String(parts[1]) // e.g. "+10,3"
            guard newPart.hasPrefix("+") else { continue }
            let newNums = newPart.dropFirst().split(separator: ",")
            let newStart = Int(newNums[0]) ?? 0
            let newCount = newNums.count > 1 ? (Int(newNums[1]) ?? 1) : 1

            // Parse -oldStart,oldCount
            let oldPart = String(parts[0]) // e.g. "-5,2"
            guard oldPart.hasPrefix("-") else { continue }
            let oldNums = oldPart.dropFirst().split(separator: ",")
            let oldCount = oldNums.count > 1 ? (Int(oldNums[1]) ?? 1) : 1

            let changeType: GitGutterChangeType
            if oldCount == 0 {
                changeType = .added
            } else if newCount == 0 {
                changeType = .deleted
            } else {
                changeType = .modified
            }

            // Convert to 0-based line numbers
            let startLine = max(newStart - 1, 0)
            let count = max(newCount, 1) // deleted hunks show at least 1 line marker

            hunks.append(GitGutterHunk(startLine: startLine, lineCount: count, changeType: changeType))
        }

        return hunks
    }
}
