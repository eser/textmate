// SW³ TextFellow — AI Edit Extension Protocol
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Defines the extension protocol for AI-powered code editing.
// AI providers implement this as WASM extensions, keeping the
// editor cloud-agnostic. Users bring their own LLM backend.
//
// Flow: Select code → ⌘K ! → describe change → inline ghost diff
//       Accept (Enter) → apply. Reject (Escape) → dismiss.

import AppKit

// MARK: - AI Edit Request/Response

/// Request sent to an AI edit extension.
public struct AIEditRequest: Codable, Sendable {
    /// The selected source code to edit.
    public let selectedText: String
    /// The user's natural language instruction.
    public let prompt: String
    /// File path for context.
    public let filePath: String?
    /// Language identifier (e.g., "swift", "python").
    public let language: String?

    public init(selectedText: String, prompt: String, filePath: String? = nil, language: String? = nil) {
        self.selectedText = selectedText
        self.prompt = prompt
        self.filePath = filePath
        self.language = language
    }
}

/// Response from an AI edit extension.
public struct AIEditResponse: Codable, Sendable {
    /// The replacement text (full replacement for the selected range).
    public let replacementText: String
    /// Optional explanation of what changed.
    public let explanation: String?

    public init(replacementText: String, explanation: String? = nil) {
        self.replacementText = replacementText
        self.explanation = explanation
    }
}

// MARK: - AI Edit Diff

/// Represents a line-level diff for inline ghost text rendering.
public struct AIEditDiffLine: Sendable {
    public enum Kind: Sendable { case unchanged, added, deleted }
    public let text: String
    public let kind: Kind
}

/// Compute a simple line-level diff between original and replacement text.
public func computeAIEditDiff(original: String, replacement: String) -> [AIEditDiffLine] {
    let origLines = original.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    let replLines = replacement.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

    var diff: [AIEditDiffLine] = []

    // Simple LCS-based diff
    let m = origLines.count
    let n = replLines.count
    var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

    for i in 1...max(m, 1) where i <= m {
        for j in 1...max(n, 1) where j <= n {
            if origLines[i - 1] == replLines[j - 1] {
                dp[i][j] = dp[i - 1][j - 1] + 1
            } else {
                dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
            }
        }
    }

    // Backtrack to produce diff
    var i = m, j = n
    var result: [AIEditDiffLine] = []

    while i > 0 || j > 0 {
        if i > 0 && j > 0 && origLines[i - 1] == replLines[j - 1] {
            result.append(AIEditDiffLine(text: origLines[i - 1], kind: .unchanged))
            i -= 1; j -= 1
        } else if j > 0 && (i == 0 || dp[i][j - 1] >= dp[i - 1][j]) {
            result.append(AIEditDiffLine(text: replLines[j - 1], kind: .added))
            j -= 1
        } else if i > 0 {
            result.append(AIEditDiffLine(text: origLines[i - 1], kind: .deleted))
            i -= 1
        }
    }

    return result.reversed()
}

// MARK: - AI Edit Manager

/// Manages the AI edit flow: request → loading → diff preview → accept/reject.
@objc(SW3TAIEditManager)
public class AIEditManager: NSObject, @unchecked Sendable {

    @objc public static let shared = AIEditManager()

    /// Current state of the AI edit flow.
    public enum State: Sendable {
        case idle
        case loading(prompt: String)
        case previewing(diff: [AIEditDiffLine], originalRange: NSRange)
        case error(message: String)
    }

    private(set) var state: State = .idle

    /// Request an AI edit. Call from ⌘K ! mode.
    @objc public func requestEdit(
        selectedText: String,
        prompt: String,
        filePath: String?,
        language: String?,
        completion: @escaping (String?, String?) -> Void  // (replacement, error)
    ) {
        state = .loading(prompt: prompt)

        // Dispatch to WASM extension host
        DispatchQueue.global(qos: .userInitiated).async {
            // TODO: Route through ExtensionHost WASM runner.
            // For now, return the selected text unchanged with a placeholder message.
            // This will be replaced by actual WASM extension invocation.
            let response: String? = nil
            let error = "No AI extension installed. Install an AI provider extension to enable ⌘K ! editing."

            DispatchQueue.main.async { [weak self] in
                if let replacement = response {
                    self?.state = .idle
                    completion(replacement, nil)
                } else {
                    self?.state = .error(message: error ?? "Unknown error")
                    completion(nil, error)
                }
            }
        }
    }

    /// Accept the current diff preview.
    @objc public func acceptEdit() {
        state = .idle
    }

    /// Reject/dismiss the current diff preview.
    @objc public func rejectEdit() {
        state = .idle
    }
}
