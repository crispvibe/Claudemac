import SwiftUI

struct ProjectSidebarView: View {
    @EnvironmentObject private var appState: AppState
    @State private var projectToRemove: ProjectItem?
    @State private var historyToRemove: CLIHistorySession?

    var body: some View {
        GlassPanel {
            VStack(spacing: 0) {
                projectSection
                    .padding(.horizontal, 14)
                    .padding(.top, 14)
                    .padding(.bottom, 12)

                Divider().opacity(0.24)
                    .padding(.horizontal, 14)

                fileSection
                    .padding(.horizontal, 10)
                    .padding(.top, 12)
                    .padding(.bottom, 12)

                Spacer(minLength: 0)

                Divider().opacity(0.24)
                    .padding(.horizontal, 14)

                settingsButton
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
        }
        .alert("移除项目？", isPresented: Binding(
            get: { projectToRemove != nil },
            set: { if !$0 { projectToRemove = nil } }
        )) {
            Button("取消", role: .cancel) { projectToRemove = nil }
            Button("移除", role: .destructive) {
                if let project = projectToRemove {
                    appState.removeProject(project)
                }
                projectToRemove = nil
            }
        } message: {
            Text("只会从 ClaudeMac 的项目列表移除“\(projectToRemove?.name ?? "该项目")”，不会删除磁盘上的文件夹。")
        }
        .alert("删除历史会话？", isPresented: Binding(
            get: { historyToRemove != nil },
            set: { if !$0 { historyToRemove = nil } }
        )) {
            Button("取消", role: .cancel) { historyToRemove = nil }
            Button("删除") {
                let session = historyToRemove
                historyToRemove = nil
                if let session {
                    appState.deleteCLIHistory(session)
                }
            }
        } message: {
            Text("会从本地 CLI 历史中删除“\(historyToRemove?.title ?? "该会话")”。")
        }
    }

    private var projectSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("项目")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(action: appState.addProject) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(AppTheme.controlSurface)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(AppTheme.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            if appState.projects.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 24))
                        .foregroundStyle(.tertiary)
                    Text("添加一个项目开始")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 6) {
                        ForEach(appState.projects) { project in
                            ProjectRow(
                                project: project,
                                sessions: sessions(for: project),
                                selectedSessionID: appState.selectedCLIHistoryID,
                                isSelected: project.id == appState.selectedProjectID,
                                onSelect: { appState.selectProject(project) },
                                onNewChat: { appState.startNewChat(for: project) },
                                onRemove: { projectToRemove = project },
                                onSelectSession: { appState.selectCLIHistory($0) },
                                onRemoveSession: { historyToRemove = $0 }
                            )
                        }
                    }
                }
                .frame(maxHeight: 210)
            }
        }
    }

    private func sessions(for project: ProjectItem) -> [CLIHistorySession] {
        let projectPath = normalizedPath(project.path)
        let key = storageKey(for: project.path)
        return appState.cliHistory.filter { session in
            if let sessionPath = session.projectPath, normalizedPath(sessionPath) == projectPath {
                return true
            }
            return session.storageKey == key
        }
    }

    private func normalizedPath(_ value: String) -> String {
        (value as NSString).standardizingPath
    }

    private func storageKey(for projectPath: String) -> String {
        "-" + normalizedPath(projectPath).trimmingCharacters(in: CharacterSet(charactersIn: "/")).replacingOccurrences(of: "/", with: "-")
    }

    private var fileSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("文件")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(action: appState.refreshFileTree) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 28, height: 28)
                        .background(AppTheme.controlSurface)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(AppTheme.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if appState.selectedProject == nil {
                        Text("未选择项目")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .padding(11)
                    } else if appState.rootNodes.isEmpty {
                        Text("没有可显示的文件")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .padding(11)
                    } else {
                        ForEach(appState.rootNodes) { node in
                            FileTreeItemView(node: node, level: 0)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var settingsButton: some View {
        Button(action: { appState.showSettings = true }) {
            HStack(spacing: 8) {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .medium))
                Text("设置")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
            }
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ProjectRow: View {
    let project: ProjectItem
    let sessions: [CLIHistorySession]
    let selectedSessionID: String?
    let isSelected: Bool
    let onSelect: () -> Void
    let onNewChat: () -> Void
    let onRemove: () -> Void
    let onSelectSession: (CLIHistorySession) -> Void
    let onRemoveSession: (CLIHistorySession) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Button(action: onSelect) {
                    HStack(spacing: 9) {
                        Image(systemName: "folder")
                            .font(.system(size: 13))
                            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                        Text(project.name)
                            .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, 11)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)

                sidebarIconButton(systemImage: "plus", help: "新建会话", action: onNewChat)
                sidebarIconButton(systemImage: "trash", help: "从列表移除项目，不删除文件夹", action: onRemove)
                    .padding(.trailing, 8)
            }
            .background(isSelected ? AppTheme.selectedSurface : Color.white.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AppTheme.weakHairline, lineWidth: 1)
            )

            if !sessions.isEmpty {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(sessions) { session in
                        HistorySessionRow(
                            session: session,
                            isSelected: selectedSessionID == session.id,
                            onSelect: { onSelectSession(session) },
                            onRemove: { onRemoveSession(session) }
                        )
                    }
                }
                .padding(.leading, 31)
                .padding(.top, 2)
            }
        }
    }

    private func sidebarIconButton(systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .medium))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tertiary)
        .contentShape(Circle())
        .help(help)
    }
}

private struct HistorySessionRow: View {
    let session: CLIHistorySession
    let isSelected: Bool
    let onSelect: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onSelect) {
                HStack(spacing: 8) {
                    Text(session.title)
                        .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(session.relativeUpdatedText)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                .foregroundStyle(isSelected ? .primary : .secondary)
                .padding(.leading, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)

            Button(action: onRemove) {
                Image(systemName: "trash")
                    .font(.system(size: 9, weight: .medium))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .contentShape(Circle())
            .help("删除历史会话")
        }
        .padding(.trailing, 6)
        .background(isSelected ? AppTheme.selectedSurface.opacity(0.78) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
