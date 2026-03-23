// SW³ TextFellow for iOS/iPadOS
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Uses shared Swift modules: SW3TTextEngine for storage,
// SW3TConfig for layered settings. No AppKit — SwiftUI only.

import SwiftUI
import UniformTypeIdentifiers

@main
struct TextFellowApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: TextDocument()) { config in
            EditorView(document: config.$document)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button("New File", systemImage: "doc.badge.plus") {}
                            Divider()
                            Button("Settings", systemImage: "gear") {}
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
        }
    }
}

// MARK: - Document

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

// MARK: - Editor View

struct EditorView: View {
    @Binding var document: TextDocument
    @State private var lineCount: Int = 1
    @State private var cursorPosition: String = "1:1"

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $document.text)
                .font(.system(size: 14, design: .monospaced))
                .scrollContentBackground(.hidden)
                .onChange(of: document.text) { _, newValue in
                    lineCount = newValue.components(separatedBy: "\n").count
                }

            // Status bar
            HStack {
                Text("Line: \(cursorPosition)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(detectLanguage())
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("UTF-8")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("\(lineCount) lines")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(.bar)
        }
    }

    private func detectLanguage() -> String {
        "Plain Text"
    }
}
