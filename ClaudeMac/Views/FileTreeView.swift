import SwiftUI

struct FileTreeItemView: View {
    @EnvironmentObject private var appState: AppState
    let node: FileNode
    let level: Int
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                if node.isDirectory {
                    isExpanded.toggle()
                    if isExpanded { appState.loadChildren(for: node) }
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
                        Image(systemName: "doc.text")
                            .font(.system(size: 13))
                            .foregroundStyle(fileColor)
                            .padding(.leading, 18)
                    }
                    Text(node.name)
                        .font(.system(size: 13))
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

    private var fileColor: Color {
        switch node.url.pathExtension.lowercased() {
        case "swift": .orange
        case "go": .cyan
        case "md", "markdown": .blue
        case "json", "plist": .purple
        default: .secondary
        }
    }
}
