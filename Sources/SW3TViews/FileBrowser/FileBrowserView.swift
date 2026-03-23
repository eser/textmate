// SW³ TextFellow — File Browser Sidebar
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Faithful reproduction of TextMate's FileBrowserViewController:
// - NSOutlineView-style hierarchical tree
// - 16x16 file icons
// - Standard row height (~17px)
// - System selection highlight
// - SCM status badges
// - Standard indentation per level

import SwiftUI
import SW3TTextEngine

/// A node in the file tree.
public struct FileNode: Identifiable, Hashable {
    public let id: ULID
    public let name: String
    public let isDirectory: Bool
    public let children: [FileNode]?
    public var scmStatus: SCMStatus

    public init(
        id: ULID = ULID(),
        name: String,
        isDirectory: Bool = false,
        children: [FileNode]? = nil,
        scmStatus: SCMStatus = .none
    ) {
        self.id = id
        self.name = name
        self.isDirectory = isDirectory
        self.children = children
        self.scmStatus = scmStatus
    }

    /// File extension for icon selection.
    public var fileExtension: String {
        (name as NSString).pathExtension
    }

    /// Children accessor for OutlineGroup — returns nil for files
    /// so OutlineGroup treats them as leaves (no disclosure triangle).
    public var optionalChildren: [FileNode]? {
        isDirectory ? children : nil
    }
}

/// SCM status badge — matches TextMate's FileBrowser SCM integration.
public enum SCMStatus: Hashable {
    case none
    case modified
    case added
    case deleted
    case untracked
    case conflicted

    public var color: Color {
        switch self {
        case .none: return .clear
        case .modified: return .blue
        case .added: return .green
        case .deleted: return .red
        case .untracked: return .secondary
        case .conflicted: return .orange
        }
    }

    public var symbol: String {
        switch self {
        case .none: return ""
        case .modified: return "M"
        case .added: return "A"
        case .deleted: return "D"
        case .untracked: return "?"
        case .conflicted: return "!"
        }
    }
}

/// TextMate-faithful file browser sidebar.
///
/// Matches FileBrowserViewController:
/// - Hierarchical outline with disclosure triangles
/// - 16x16 file/folder icons
/// - System selection color
/// - SCM status badges
/// - Standard row height (~17px)
public struct FileBrowserView: View {
    let root: [FileNode]
    @Binding var selection: Set<ULID>
    var onOpen: ((FileNode) -> Void)?

    public init(
        root: [FileNode],
        selection: Binding<Set<ULID>>,
        onOpen: ((FileNode) -> Void)? = nil
    ) {
        self.root = root
        self._selection = selection
        self.onOpen = onOpen
    }

    public var body: some View {
        List(selection: $selection) {
            OutlineGroup(root, children: \.optionalChildren) { node in
                fileRowLabel(node: node)
                    .onTapGesture(count: 2) {
                        if !node.isDirectory {
                            onOpen?(node)
                        }
                    }
            }
        }
        .listStyle(.sidebar)
        .environment(\.defaultMinListRowHeight, 17) // Match TextMate's row height
    }

    /// Individual file/folder row — matches TextMate's FileItemTableCellView.
    @ViewBuilder
    private func fileRowLabel(node: FileNode) -> some View {
        HStack(spacing: 4) {
            // 16x16 icon — matches TextMate's TMFileReference icon size
            Image(systemName: node.isDirectory ? "folder.fill" : fileIcon(for: node))
                .font(.system(size: 13))
                .foregroundStyle(node.isDirectory ? .blue : .secondary)
                .frame(width: 16, height: 16)

            // File name
            Text(node.name)
                .font(.system(size: 13))
                .lineLimit(1)

            Spacer()

            // SCM status badge — matches TextMate's SCMManager integration
            if node.scmStatus != .none {
                Text(node.scmStatus.symbol)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(node.scmStatus.color)
                    .frame(width: 14, height: 14)
            }
        }
        .frame(height: 17) // TextMate's default row height
    }

    /// Map file extensions to SF Symbols (approximating TextMate's icon behavior).
    private func fileIcon(for node: FileNode) -> String {
        switch node.fileExtension.lowercased() {
        case "swift": return "swift"
        case "js", "ts", "jsx", "tsx": return "doc.text"
        case "json": return "curlybraces"
        case "md", "markdown": return "doc.richtext"
        case "html", "htm": return "globe"
        case "css", "scss": return "paintbrush"
        case "py": return "doc.text"
        case "rb": return "doc.text"
        case "rs": return "doc.text"
        case "go": return "doc.text"
        case "c", "h", "cpp", "hpp", "cc", "mm", "m": return "doc.text"
        case "toml", "yaml", "yml": return "gearshape"
        case "sh", "zsh", "bash": return "terminal"
        case "png", "jpg", "jpeg", "gif", "svg": return "photo"
        default: return "doc"
        }
    }
}

#if DEBUG
#Preview("File Browser") {
    @Previewable @State var selection: Set<ULID> = []

    let sampleTree = [
        FileNode(name: "Sources", isDirectory: true, children: [
            FileNode(name: "SW3TTextEngine", isDirectory: true, children: [
                FileNode(name: "TextStorage.swift", scmStatus: .modified),
                FileNode(name: "EditOperation.swift"),
                FileNode(name: "TextEngineActor.swift", scmStatus: .added),
            ]),
            FileNode(name: "SW3TRenderer", isDirectory: true, children: [
                FileNode(name: "GlyphAtlas.swift"),
                FileNode(name: "Shaders.metal"),
            ]),
        ]),
        FileNode(name: "Package.swift", scmStatus: .modified),
        FileNode(name: "README.md"),
        FileNode(name: "SPEC.md", scmStatus: .added),
    ]

    FileBrowserView(root: sampleTree, selection: $selection) { node in
        print("Open: \(node.name)")
    }
    .frame(width: 250, height: 400)
}
#endif
