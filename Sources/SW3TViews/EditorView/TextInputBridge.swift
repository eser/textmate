// SW³ TextFellow — Text Input Bridge (NSTextInputClient)
// SPDX-License-Identifier: GPL-3.0-or-later
//
// One of the 3 AppKit edge cases (SPEC.md §11).
// Invisible NSView implementing NSTextInputClient for keyboard input.

#if canImport(AppKit)
import AppKit
import SwiftUI

/// Callback interface for text input events.
public protocol TextInputHandler: AnyObject {
    func insertText(_ text: String)
    func deleteBackward()
    func deleteForward()
    func moveUp()
    func moveDown()
    func moveLeft()
    func moveRight()
    func moveToBeginningOfLine()
    func moveToEndOfLine()
    func insertNewline()
    func insertTab()
}

/// Invisible NSView that captures keyboard input via NSTextInputClient.
@MainActor
public class TextInputView: NSView, @preconcurrency NSTextInputClient {
    public weak var inputHandler: TextInputHandler?

    private var _markedText: NSMutableAttributedString = NSMutableAttributedString()
    private var _markedRange: NSRange = NSRange(location: NSNotFound, length: 0)
    private var _selectedRange: NSRange = NSRange(location: 0, length: 0)

    public override var acceptsFirstResponder: Bool { true }
    public override func becomeFirstResponder() -> Bool { true }

    public override func keyDown(with event: NSEvent) {
        interpretKeyEvents([event])
    }

    // MARK: - Key bindings (cursor movement, delete)

    public override func moveUp(_ sender: Any?) { inputHandler?.moveUp() }
    public override func moveDown(_ sender: Any?) { inputHandler?.moveDown() }
    public override func moveLeft(_ sender: Any?) { inputHandler?.moveLeft() }
    public override func moveRight(_ sender: Any?) { inputHandler?.moveRight() }
    public override func moveToBeginningOfLine(_ sender: Any?) { inputHandler?.moveToBeginningOfLine() }
    public override func moveToEndOfLine(_ sender: Any?) { inputHandler?.moveToEndOfLine() }
    public override func deleteBackward(_ sender: Any?) { inputHandler?.deleteBackward() }
    public override func deleteForward(_ sender: Any?) { inputHandler?.deleteForward() }
    public override func insertNewline(_ sender: Any?) { inputHandler?.insertNewline() }
    public override func insertTab(_ sender: Any?) { inputHandler?.insertTab() }

    // MARK: - NSTextInputClient

    public func insertText(_ string: Any, replacementRange: NSRange) {
        let text: String
        if let s = string as? NSAttributedString { text = s.string }
        else if let s = string as? String { text = s }
        else { return }

        _markedText = NSMutableAttributedString()
        _markedRange = NSRange(location: NSNotFound, length: 0)
        inputHandler?.insertText(text)
    }

    public func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        if let s = string as? NSAttributedString {
            _markedText = NSMutableAttributedString(attributedString: s)
        } else if let s = string as? String {
            _markedText = NSMutableAttributedString(string: s)
        }
        _markedRange = NSRange(location: 0, length: _markedText.length)
        _selectedRange = selectedRange
    }

    public func unmarkText() {
        _markedText = NSMutableAttributedString()
        _markedRange = NSRange(location: NSNotFound, length: 0)
    }

    public func selectedRange() -> NSRange { _selectedRange }
    public func markedRange() -> NSRange { _markedRange }
    public func hasMarkedText() -> Bool { _markedRange.location != NSNotFound && _markedRange.length > 0 }

    public func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? { nil }
    public func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }

    public func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let window = self.window else { return .zero }
        return NSRect(x: window.frame.minX + 60, y: window.frame.minY + 40, width: 1, height: 20)
    }

    public func characterIndex(for point: NSPoint) -> Int { 0 }
}

/// SwiftUI wrapper — invisible, captures keyboard.
public struct TextInputBridgeView: NSViewRepresentable {
    let inputHandler: TextInputHandler

    public init(inputHandler: TextInputHandler) {
        self.inputHandler = inputHandler
    }

    public func makeNSView(context: Context) -> TextInputView {
        let view = TextInputView()
        view.inputHandler = inputHandler
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    public func updateNSView(_ nsView: TextInputView, context: Context) {
        nsView.inputHandler = inputHandler
    }
}
#endif
