import SwiftUI

struct FileTreeItemView: View {
    @EnvironmentObject private var appState: AppState
    let node: FileNode
    let level: Int

    private var isExpanded: Bool {
        appState.isFileTreeNodeExpanded(node)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                if node.isDirectory {
                    appState.toggleFileTreeNode(node)
                } else {
                    appState.openFile(node)
                }
            } label: {
                HStack(spacing: 7) {
                    if node.isDirectory {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .frame(width: 11)
                        Image(systemName: "folder")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: fileIconName)
                            .font(.system(size: 13))
                            .foregroundStyle(fileIconColor)
                            .frame(width: 13)
                            .padding(.leading, 18)
                    }
                    Text(node.name)
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.fileTreeName)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.leading, CGFloat(level) * 14 + 7)
                .padding(.trailing, 8)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .background(isOpenFile ? AppTheme.selectedSurface : Color.white.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .onDrag {
                NSItemProvider(object: node.url.path as NSString)
            }
            .onAppear {
                appState.restoreExpandedFileTreeNode(node)
            }

            if node.isDirectory && isExpanded {
                let children = appState.childCache[node.id] ?? []
                if children.isEmpty {
                    Text("空文件夹")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, CGFloat(level + 1) * 14 + 32)
                        .padding(.vertical, 5)
                } else {
                    ForEach(children) { child in
                        FileTreeItemView(node: child, level: level + 1)
                    }
                }
            }
        }
    }

    private var isOpenFile: Bool {
        appState.selectedTab?.url == node.url
    }

    private var fileIconName: String {
        switch node.url.pathExtension.lowercased() {
        case "swift": "swift"
        case "js", "jsx", "ts", "tsx": "curlybraces"
        case "json", "plist", "yaml", "yml", "toml": "list.bullet.rectangle"
        case "md", "markdown", "txt": "doc.richtext"
        case "html", "htm", "xml": "chevron.left.forwardslash.chevron.right"
        case "css", "scss", "sass", "less": "paintbrush"
        case "py": "terminal"
        case "go", "rs", "java", "kt", "kts", "c", "cc", "cpp", "h", "hpp", "cs", "rb", "php": "chevron.left.slash.chevron.right"
        case "png", "jpg", "jpeg", "gif", "webp", "svg", "pdf": "photo"
        default: "doc.text"
        }
    }

    private var fileIconColor: Color {
        switch node.url.pathExtension.lowercased() {
        case "swift": .orange
        case "js", "jsx": .yellow
        case "ts", "tsx": .blue
        case "json", "plist", "yaml", "yml", "toml": .purple
        case "md", "markdown", "txt": .mint
        case "html", "htm", "xml": .red
        case "css", "scss", "sass", "less": .indigo
        case "py": .green
        case "go": .cyan
        case "rs": .brown
        case "java", "kt", "kts": .pink
        case "c", "cc", "cpp", "h", "hpp", "cs": .teal
        case "rb", "php": .purple
        case "png", "jpg", "jpeg", "gif", "webp", "svg", "pdf": .orange
        default: .secondary
        }
    }
}
