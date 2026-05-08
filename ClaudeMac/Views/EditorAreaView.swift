import SwiftUI

struct EditorAreaView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            if let tab = appState.selectedTab {
                TextEditorRepresentable(
                    text: appState.bindingForTabText(tab.id),
                    fileName: tab.title,
                    onTextChange: { _ in },
                    onCursorChange: { line, column in
                        appState.cursorLine = line
                        appState.cursorColumn = column
                    }
                )
                .background(AppTheme.editorSurface)
            } else {
                emptyEditor
            }

            Divider().opacity(0.24)
            statusBar
        }
        .background(AppTheme.editorSurface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppTheme.hairline, lineWidth: 1)
        )
    }

    private var emptyEditor: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 26))
                .foregroundStyle(.tertiary)
            Text("从左侧文件树打开文本文件")
                .font(.system(size: 13, weight: .medium))
            Text("快速查看、轻量编辑，并从右侧启动 AI CLI 会话。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.editorSurface)
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            if let tab = appState.selectedTab {
                Text(tab.title)
                    .lineLimit(1)
                Text(fileSizeText(for: tab.text))
                Text("\(lineCount(for: tab.text)) 行")
                Text("第 \(appState.cursorLine) 行，第 \(appState.cursorColumn) 列")
                Spacer()
                Text("修改于\(relativeModifiedText(tab.modifiedAt))")
            } else {
                Text("未打开文件")
                Spacer()
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(AppTheme.editorSurface)
    }

    private func lineCount(for text: String) -> Int {
        max(1, text.components(separatedBy: .newlines).count)
    }

    private func fileSizeText(for text: String) -> String {
        let byteCount = text.data(using: .utf8)?.count ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }

    private func relativeModifiedText(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
