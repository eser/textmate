// SW³ TextFellow — LSP Hover Tooltip
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Renders hover information from LSP servers as a floating tooltip.
// Supports plain text and basic markdown rendering.
// Triggered by mouse hover (500ms delay) or keyboard (Ctrl+I).

import AppKit
import SwiftUI

// MARK: - Hover Content View

struct HoverContentView: View {
    let contents: String
    let isMarkdown: Bool

    var body: some View {
        ScrollView {
            if isMarkdown {
                // Basic markdown: render code blocks with monospace, headers with bold
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(parseMarkdown(contents).enumerated()), id: \.offset) { _, block in
                        switch block {
                        case .code(let text):
                            Text(text)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.primary)
                                .padding(6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.primary.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 4))

                        case .text(let text):
                            Text(text)
                                .font(.system(size: 11))
                                .foregroundStyle(.primary)

                        case .heading(let text):
                            Text(text)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.primary)
                        }
                    }
                }
                .padding(8)
            } else {
                Text(contents)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.primary)
                    .padding(8)
            }
        }
        .frame(maxWidth: 450, maxHeight: 300)
        .background(.regularMaterial)
    }
}

// MARK: - Simple Markdown Parser

private enum MarkdownBlock {
    case code(String)
    case text(String)
    case heading(String)
}

private func parseMarkdown(_ input: String) -> [MarkdownBlock] {
    var blocks: [MarkdownBlock] = []
    var lines = input.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    var i = 0

    while i < lines.count {
        let line = lines[i]

        // Code block (``` ... ```)
        if line.hasPrefix("```") {
            var code = ""
            i += 1
            while i < lines.count && !lines[i].hasPrefix("```") {
                if !code.isEmpty { code += "\n" }
                code += lines[i]
                i += 1
            }
            if !code.isEmpty {
                blocks.append(.code(code))
            }
            i += 1 // skip closing ```
            continue
        }

        // Heading (# ...)
        if line.hasPrefix("#") {
            let text = line.drop(while: { $0 == "#" || $0 == " " })
            blocks.append(.heading(String(text)))
            i += 1
            continue
        }

        // Regular text — collect consecutive non-empty lines
        var text = line
        i += 1
        while i < lines.count && !lines[i].hasPrefix("```") && !lines[i].hasPrefix("#") && !lines[i].isEmpty {
            text += " " + lines[i]
            i += 1
        }

        if !text.trimmingCharacters(in: .whitespaces).isEmpty {
            blocks.append(.text(text))
        } else {
            i += 1 // skip empty line
        }
    }

    return blocks
}

// MARK: - Hover Tooltip Controller

@objc(SW3THoverController)
public class HoverController: NSObject, @unchecked Sendable {

    @objc public static let shared = HoverController()

    private var panel: NSPanel?
    private var hoverTimer: Timer?

    /// Show hover tooltip at a screen position.
    @objc public func show(contents: String, isMarkdown: Bool, at screenPoint: NSPoint, in parentWindow: NSWindow) {
        dismiss()

        let view = HoverContentView(contents: contents, isMarkdown: isMarkdown)
        let hosting = NSHostingView(rootView: view)

        let size = hosting.fittingSize
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: min(size.width, 450), height: min(size.height, 300))),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hidesOnDeactivate = true
        panel.contentView = hosting

        // Position above the cursor
        panel.setFrameOrigin(NSPoint(x: screenPoint.x, y: screenPoint.y + 4))
        parentWindow.addChildWindow(panel, ordered: .above)
        panel.orderFront(nil)

        self.panel = panel
    }

    /// ObjC-compatible show method.
    @objc(showHover:at:in:)
    public func showHover(_ contents: String, at screenPoint: NSPoint, in parentWindow: NSWindow) {
        // Auto-detect markdown (contains ``` or # heading)
        let isMarkdown = contents.contains("```") || contents.contains("\n# ") || contents.hasPrefix("# ")
        show(contents: contents, isMarkdown: isMarkdown, at: screenPoint, in: parentWindow)
    }

    /// Dismiss the hover tooltip.
    @objc public func dismiss() {
        hoverTimer?.invalidate()
        hoverTimer = nil
        panel?.parent?.removeChildWindow(panel!)
        panel?.orderOut(nil)
        panel = nil
    }

    /// Schedule a hover tooltip with a delay (for mouse hover).
    @objc public func scheduleHover(
        contents: String,
        at screenPoint: NSPoint,
        in parentWindow: NSWindow,
        delay: TimeInterval = 0.5
    ) {
        dismiss()
        hoverTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.showHover(contents, at: screenPoint, in: parentWindow)
        }
    }

    /// Whether the tooltip is currently visible.
    @objc public var isVisible: Bool { panel?.isVisible ?? false }
}
