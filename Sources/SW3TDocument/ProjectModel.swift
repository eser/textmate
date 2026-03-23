// SW³ TextFellow — Project Model
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SW3TTextEngine

/// Represents an open project (folder).
///
/// TextMate uses a folder-based project model — open a directory,
/// that's your project. No .tmproj files required.
@Observable
public final class ProjectModel {
    /// Root URL of the project folder.
    public private(set) var rootURL: URL?

    /// Scanned file tree for the sidebar.
    public private(set) var fileTree: [FileTreeNode] = []

    /// Currently open documents, keyed by file URL.
    public private(set) var openDocuments: [URL: OpenDocument] = [:]

    /// URL of the currently active (focused) document.
    public var activeDocumentURL: URL?

    private let fileService: FileService

    public init(fileService: FileService = FileService()) {
        self.fileService = fileService
    }

    /// Open a folder as a project. Scans the directory tree.
    public func openFolder(_ url: URL) throws {
        rootURL = url
        fileTree = try fileService.scanDirectory(at: url)
    }

    /// Open a file for editing. Creates a TextEditSession for it.
    @TextEngineActor
    public func openFile(at url: URL) throws -> OpenDocument {
        if let existing = openDocuments[url] {
            return existing
        }

        let content = try fileService.readFile(at: url)
        let session = TextEditSession(text: content)
        let doc = OpenDocument(
            url: url,
            name: url.lastPathComponent,
            session: session
        )
        openDocuments[url] = doc
        activeDocumentURL = url
        return doc
    }

    /// Save the active document.
    @TextEngineActor
    public func saveDocument(at url: URL) throws {
        guard let doc = openDocuments[url] else { return }
        let content = doc.session.text
        try fileService.writeFile(content, to: url)
        doc.isModified = false
    }

    /// Close a document.
    public func closeDocument(at url: URL) {
        openDocuments.removeValue(forKey: url)
        if activeDocumentURL == url {
            activeDocumentURL = openDocuments.keys.first
        }
    }
}

/// An open document with its editing session.
@Observable
public final class OpenDocument {
    public let url: URL
    public let name: String
    public let session: TextEditSession
    public var isModified: Bool = false

    public init(url: URL, name: String, session: TextEditSession) {
        self.url = url
        self.name = name
        self.session = session
    }
}
