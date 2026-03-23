import Foundation
import AppKit

// MARK: - Theme Colors

/// Standard syntax token colors for a theme.
/// All colors are system-adaptive, meaning they respond to dark/light mode changes.
@objc public final class ThemeColors: NSObject, @unchecked Sendable {

    @objc public let keyword: NSColor
    @objc public let string: NSColor
    @objc public let number: NSColor
    @objc public let comment: NSColor
    @objc public let type: NSColor
    @objc public let function: NSColor
    @objc public let variable: NSColor
    @objc public let `operator`: NSColor
    @objc public let punctuation: NSColor
    @objc public let plain: NSColor

    @objc public init(keyword: NSColor,
                      string: NSColor,
                      number: NSColor,
                      comment: NSColor,
                      type: NSColor,
                      function: NSColor,
                      variable: NSColor,
                      operator op: NSColor,
                      punctuation: NSColor,
                      plain: NSColor) {
        self.keyword = keyword
        self.string = string
        self.number = number
        self.comment = comment
        self.type = type
        self.function = function
        self.variable = variable
        self.operator = op
        self.punctuation = punctuation
        self.plain = plain
    }

    /// A default theme using system-adaptive colors that automatically adjust
    /// between light and dark mode via `NSColor(name:dynamicProvider:)`.
    @objc public static let `default`: ThemeColors = {
        ThemeColors(
            keyword:     adaptive(light: (0.78, 0.14, 0.60), dark: (1.00, 0.47, 0.78)),
            string:      adaptive(light: (0.77, 0.10, 0.09), dark: (1.00, 0.42, 0.42)),
            number:      adaptive(light: (0.16, 0.28, 0.77), dark: (0.56, 0.70, 1.00)),
            comment:     adaptive(light: (0.42, 0.47, 0.51), dark: (0.55, 0.60, 0.65)),
            type:        adaptive(light: (0.11, 0.43, 0.60), dark: (0.42, 0.78, 0.94)),
            function:    adaptive(light: (0.27, 0.38, 0.08), dark: (0.54, 0.76, 0.29)),
            variable:    adaptive(light: (0.10, 0.10, 0.10), dark: (0.88, 0.88, 0.88)),
            operator:    adaptive(light: (0.20, 0.20, 0.20), dark: (0.80, 0.80, 0.80)),
            punctuation: adaptive(light: (0.30, 0.30, 0.30), dark: (0.70, 0.70, 0.70)),
            plain:       adaptive(light: (0.10, 0.10, 0.10), dark: (0.90, 0.90, 0.90))
        )
    }()

    private static func adaptive(light: (CGFloat, CGFloat, CGFloat),
                                  dark: (CGFloat, CGFloat, CGFloat)) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let (r, g, b) = isDark ? dark : light
            return NSColor(srgbRed: r, green: g, blue: b, alpha: 1.0)
        }
    }
}

// MARK: - Syntax Token

/// A parsed syntax token produced by a tree-sitter query or similar parser.
/// Provides the node type and byte range within the source text.
@objc public final class SyntaxToken: NSObject {
    /// The tree-sitter node type, e.g. "string_content", "number_literal", "keyword".
    @objc public let nodeType: String
    /// Byte offset range in the source buffer.
    @objc public let startByte: Int
    @objc public let endByte: Int

    @objc public init(nodeType: String, startByte: Int, endByte: Int) {
        self.nodeType = nodeType
        self.startByte = startByte
        self.endByte = endByte
    }
}

// MARK: - Colorized Span

/// Result of colorizing: a range paired with a resolved color.
@objc public final class ColorizedSpan: NSObject {
    @objc public let location: Int
    @objc public let length: Int
    @objc public let color: NSColor

    @objc public init(location: Int, length: Int, color: NSColor) {
        self.location = location
        self.length = length
        self.color = color
    }

    /// Convenience accessor for the range as `Range<Int>`.
    public var range: Range<Int> { location..<(location + length) }
}

// MARK: - Node Type Classification

/// Categorizes tree-sitter node types into semantic token kinds.
private enum SemanticKind {
    case keyword
    case string
    case number
    case comment
    case type
    case function
    case variable
    case `operator`
    case punctuation
    case plain

    /// Map a tree-sitter node type string to a semantic kind.
    /// This mapping covers common grammars (C, C++, Swift, Rust, JS/TS, Python, Ruby, Go, etc.).
    static func classify(_ nodeType: String) -> SemanticKind {
        // Exact matches for common node types.
        switch nodeType {
        // Keywords
        case "keyword", "modifier", "storage_type", "type_qualifier",
             "break_statement", "continue_statement", "return_statement",
             "if", "else", "for", "while", "do", "switch", "case", "default",
             "import", "package", "module", "using", "namespace",
             "class_keyword", "struct_keyword", "enum_keyword", "protocol",
             "func_keyword", "let_keyword", "var_keyword",
             "public", "private", "protected", "internal", "static", "final",
             "async", "await", "try", "catch", "throw", "throws",
             "true", "false", "nil", "null", "none", "self", "super":
            return .keyword

        // String literals and content
        case "string_literal", "string_content", "string", "raw_string_literal",
             "string_fragment", "template_string", "heredoc_body",
             "char_literal", "character_literal",
             "escape_sequence", "string_special_key", "interpolation":
            return .string

        // Numbers
        case "number_literal", "integer_literal", "float_literal",
             "number", "integer", "float", "decimal_integer_literal",
             "hex_integer_literal", "binary_integer_literal", "octal_integer_literal",
             "decimal_floating_point_literal":
            return .number

        // Comments
        case "comment", "line_comment", "block_comment", "doc_comment",
             "documentation_comment", "multiline_comment":
            return .comment

        // Types
        case "type_identifier", "primitive_type", "builtin_type",
             "class_declaration", "struct_declaration", "enum_declaration",
             "type_alias_declaration", "interface_declaration",
             "generic_type", "scoped_type_identifier",
             "simple_type", "user_type":
            return .type

        // Functions
        case "function_declaration", "method_declaration",
             "function_definition", "method_definition",
             "call_expression", "function_call",
             "function_identifier", "method_identifier":
            return .function

        // Variables and identifiers
        case "identifier", "variable_declaration", "variable_declarator",
             "field_identifier", "property_identifier",
             "shorthand_property_identifier", "pattern",
             "simple_identifier":
            return .variable

        // Operators
        case "binary_operator", "unary_operator", "ternary_expression",
             "comparison_operator", "assignment_operator",
             "arithmetic_operator", "logical_operator",
             "bitwise_operator", "operator":
            return .operator

        // Punctuation
        case ".", ",", ";", ":", "(", ")", "[", "]", "{", "}",
             "open_paren", "close_paren", "open_bracket", "close_bracket",
             "open_brace", "close_brace", "comma", "semicolon":
            return .punctuation

        default:
            return classifyByPattern(nodeType)
        }
    }

    /// Fallback classification using substring patterns.
    private static func classifyByPattern(_ nodeType: String) -> SemanticKind {
        let lower = nodeType.lowercased()

        if lower.contains("keyword") || lower.contains("_kw") { return .keyword }
        if lower.contains("string") || lower.contains("char_") { return .string }
        if lower.contains("number") || lower.contains("integer") || lower.contains("float")
            || lower.contains("literal") && (lower.contains("int") || lower.contains("num")) { return .number }
        if lower.contains("comment") || lower.contains("doc_") { return .comment }
        if lower.contains("type") || lower.contains("class") || lower.contains("struct")
            || lower.contains("enum") || lower.contains("interface") { return .type }
        if lower.contains("function") || lower.contains("method") || lower.contains("call") { return .function }
        if lower.contains("operator") || lower.contains("_op") { return .operator }
        if lower.contains("punctuation") || lower.contains("delimiter")
            || lower.contains("bracket") || lower.contains("paren") || lower.contains("brace") { return .punctuation }
        if lower.contains("identifier") || lower.contains("variable") || lower.contains("field") { return .variable }

        return .plain
    }
}

// MARK: - Syntax Colorizer

/// Bridges tree-sitter parse results to rendering-ready colorized spans.
///
/// Usage:
/// ```swift
/// let colorizer = SyntaxColorizer()
/// let spans = colorizer.colorize(tokens: treeSitterTokens, theme: .default)
/// // Use spans to build NSAttributedString or feed to MetalTextRenderer
/// ```
@objc public final class SyntaxColorizer: NSObject {

    /// Cached mapping from node type strings to their semantic kind,
    /// avoiding repeated classification of the same node types.
    private var classificationCache: [String: SemanticKind] = [:]

    @objc public override init() {
        super.init()
    }

    /// Colorize an array of syntax tokens using the given theme.
    ///
    /// - Parameters:
    ///   - tokens: Parsed syntax tokens from a tree-sitter query.
    ///   - theme: Color scheme to apply. Defaults to the adaptive default theme.
    /// - Returns: An array of `ColorizedSpan` objects sorted by position.
    @objc public func colorize(tokens: [SyntaxToken], theme: ThemeColors = .default) -> [ColorizedSpan] {
        var spans: [ColorizedSpan] = []
        spans.reserveCapacity(tokens.count)

        for token in tokens {
            let kind = classify(token.nodeType)
            let color = resolveColor(kind: kind, theme: theme)
            let length = token.endByte - token.startByte
            guard length > 0 else { continue }
            spans.append(ColorizedSpan(location: token.startByte, length: length, color: color))
        }

        // Sort by position for efficient iteration during rendering.
        spans.sort { $0.location < $1.location }
        return spans
    }

    /// Swift-native variant returning tuple ranges instead of `ColorizedSpan` objects.
    public func colorize(tokens: [SyntaxToken],
                         theme: ThemeColors = .default) -> [(range: Range<Int>, color: NSColor)] {
        let spans: [ColorizedSpan] = colorize(tokens: tokens, theme: theme)
        return spans.map { ($0.range, $0.color) }
    }

    /// Apply colorized spans to an `NSMutableAttributedString` as foreground colors.
    @objc public func apply(spans: [ColorizedSpan], to attributedString: NSMutableAttributedString) {
        for span in spans {
            let nsRange = NSRange(location: span.location, length: span.length)
            guard nsRange.location + nsRange.length <= attributedString.length else { continue }
            attributedString.addAttribute(.foregroundColor, value: span.color, range: nsRange)
        }
    }

    // MARK: Internal

    private func classify(_ nodeType: String) -> SemanticKind {
        if let cached = classificationCache[nodeType] {
            return cached
        }
        let kind = SemanticKind.classify(nodeType)
        classificationCache[nodeType] = kind
        return kind
    }

    private func resolveColor(kind: SemanticKind, theme: ThemeColors) -> NSColor {
        switch kind {
        case .keyword:     return theme.keyword
        case .string:      return theme.string
        case .number:      return theme.number
        case .comment:     return theme.comment
        case .type:        return theme.type
        case .function:    return theme.function
        case .variable:    return theme.variable
        case .operator:    return theme.operator
        case .punctuation: return theme.punctuation
        case .plain:       return theme.plain
        }
    }
}
