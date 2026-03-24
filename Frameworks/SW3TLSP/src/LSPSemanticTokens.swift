// SW³ TextFellow — LSP Semantic Tokens
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Requests and decodes semantic tokens from LSP servers.
// Semantic tokens overlay tree-sitter highlighting with richer
// type information (parameter vs local, method vs function).

import AppKit

// MARK: - Semantic Token Types

/// Standard LSP semantic token types (indices into the server's legend).
public enum SemanticTokenType: Int, CaseIterable, Sendable {
    case namespace = 0, type, `class`, `enum`, interface
    case `struct`, typeParameter, parameter, variable, property
    case enumMember, event, function, method, macro
    case keyword, modifier, comment, string, number
    case regexp, `operator`, decorator
}

/// A decoded semantic token with absolute position.
public struct SemanticToken: Sendable {
    public let line: Int
    public let startCharacter: Int
    public let length: Int
    public let tokenType: Int
    public let tokenModifiers: Int
}

// MARK: - Semantic Token Colors

/// Maps semantic token types to NSColors using system-adaptive colors.
public struct SemanticTokenColorizer: Sendable {
    public static func color(for tokenType: Int) -> NSColor? {
        guard let type = SemanticTokenType(rawValue: tokenType) else { return nil }
        switch type {
        case .keyword, .modifier:     return .systemPurple
        case .type, .class, .struct, .enum, .interface:
                                      return .systemTeal
        case .function, .method:      return .systemBlue
        case .parameter:              return .systemOrange
        case .variable:               return .labelColor
        case .property, .enumMember:  return .systemCyan
        case .string:                 return .systemRed
        case .number:                 return .systemIndigo
        case .comment:                return .systemGray
        case .macro, .decorator:      return .systemYellow
        case .namespace:              return .secondaryLabelColor
        case .regexp:                 return .systemRed
        case .operator:               return .labelColor
        case .typeParameter:          return .systemTeal
        case .event:                  return .systemPink
        }
    }
}

// MARK: - Token Decoding

/// Decodes the delta-encoded integer array from LSP semantic tokens response.
public func decodeSemanticTokens(data: [Int]) -> [SemanticToken] {
    var tokens: [SemanticToken] = []
    guard data.count >= 5 else { return tokens }

    var currentLine = 0
    var currentChar = 0

    var i = 0
    while i + 4 < data.count {
        let deltaLine = data[i]
        let deltaStart = data[i + 1]
        let length = data[i + 2]
        let tokenType = data[i + 3]
        let tokenModifiers = data[i + 4]

        if deltaLine > 0 {
            currentLine += deltaLine
            currentChar = deltaStart
        } else {
            currentChar += deltaStart
        }

        tokens.append(SemanticToken(
            line: currentLine,
            startCharacter: currentChar,
            length: length,
            tokenType: tokenType,
            tokenModifiers: tokenModifiers
        ))

        i += 5
    }

    return tokens
}
