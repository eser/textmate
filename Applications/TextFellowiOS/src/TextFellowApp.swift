// SW³ TextFellow for iOS/iPadOS
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Minimal app shell. The shared Swift modules (SW3TSyntax, SW3TConfig,
// SW3TLSP, SW3TExtensionHost) are cross-platform and used here directly.
// The iOS UI is entirely SwiftUI — no AppKit to port.

import SwiftUI
import UniformTypeIdentifiers

@main
struct TextFellowApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: TextDocument()) { config in
            EditorView(document: config.$document)
        }
    }
}

/// A simple text document for the iOS app.
struct TextDocument: FileDocument, Sendable {
    static var readableContentTypes: [UTType] { [.plainText, .sourceCode] }

    var text: String

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            text = String(data: data, encoding: .utf8) ?? ""
        } else {
            text = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

/// Minimal editor view — TextEditor with syntax-aware styling.
struct EditorView: View {
    @Binding var document: TextDocument

    var body: some View {
        TextEditor(text: $document.text)
            .font(.system(.body, design: .monospaced))
            .scrollContentBackground(.hidden)
            .padding(4)
    }
}
