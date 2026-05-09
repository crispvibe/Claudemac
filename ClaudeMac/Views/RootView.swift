import AppKit
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("root.chatPanelWidth") private var storedChatPanelWidth = 420.0
    @State private var dragStartChatPanelWidth: CGFloat?
    @State private var isHoveringResizeHandle = false
    @State private var workbenchContentWidth: CGFloat = 0

    private let minChatPanelWidth: CGFloat = 260
    private let minEditorWidth: CGFloat = 320
    private let resizeHandleWidth: CGFloat = 12

    var body: some View {
        HStack(spacing: 6) {
            ProjectSidebarView()
                .frame(width: 228)

            if appState.showSettings {
                SettingsPageView()
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(AppTheme.hairline, lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.055), radius: 16, y: 8)
            } else {
                workbenchCard
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .frame(minWidth: 1320, minHeight: 760)
        .background {
            ZStack {
                VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                    .opacity(0.95)
                AppTheme.windowTint
            }
            .ignoresSafeArea()
        }
        .alert("提示", isPresented: Binding(
            get: { appState.errorMessage != nil },
            set: { if !$0 { appState.errorMessage = nil } }
        )) {
            Button("好") { appState.errorMessage = nil }
        } message: {
            Text(appState.errorMessage ?? "")
        }
    }

    private var workbenchCard: some View {
        VStack(spacing: 0) {
            EditorTabBarView()

            GeometryReader { proxy in
                HStack(spacing: 0) {
                    EditorAreaView()
                        .frame(minWidth: minEditorWidth, maxWidth: .infinity, maxHeight: .infinity)

                    resizeHandle

                    ChatPanelView()
                        .frame(width: clampedChatPanelWidth(CGFloat(storedChatPanelWidth), availableWidth: proxy.size.width))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    workbenchContentWidth = proxy.size.width
                    storedChatPanelWidth = Double(clampedChatPanelWidth(CGFloat(storedChatPanelWidth), availableWidth: proxy.size.width))
                }
                .onChange(of: proxy.size.width) { _, width in
                    workbenchContentWidth = width
                    storedChatPanelWidth = Double(clampedChatPanelWidth(CGFloat(storedChatPanelWidth), availableWidth: width))
                }
            }
        }
        .background(AppTheme.editorSurface.opacity(0.86))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(AppTheme.hairline, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.055), radius: 16, y: 8)
    }

    private var resizeHandle: some View {
        ZStack {
            Rectangle()
                .fill(Color.clear)
            Capsule()
                .fill(Color.black.opacity(isHoveringResizeHandle || dragStartChatPanelWidth != nil ? 0.18 : 0.07))
                .frame(width: 3, height: 46)
        }
        .frame(width: resizeHandleWidth)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHoveringResizeHandle = hovering
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        .onDisappear {
            if isHoveringResizeHandle {
                NSCursor.pop()
                isHoveringResizeHandle = false
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if dragStartChatPanelWidth == nil {
                        dragStartChatPanelWidth = CGFloat(storedChatPanelWidth)
                    }
                    let startWidth = dragStartChatPanelWidth ?? CGFloat(storedChatPanelWidth)
                    storedChatPanelWidth = Double(clampedChatPanelWidth(startWidth - value.translation.width, availableWidth: workbenchContentWidth))
                }
                .onEnded { _ in
                    dragStartChatPanelWidth = nil
                }
        )
        .help("拖动调整编辑器和对话卡片宽度")
    }

    private func clampedChatPanelWidth(_ width: CGFloat, availableWidth: CGFloat) -> CGFloat {
        let availableMax = availableWidth > 0
            ? max(minChatPanelWidth, availableWidth - minEditorWidth - resizeHandleWidth)
            : max(width, minChatPanelWidth)
        return min(max(width, minChatPanelWidth), availableMax)
    }
}
