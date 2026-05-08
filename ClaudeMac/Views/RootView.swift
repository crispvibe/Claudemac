import AppKit
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @State private var chatPanelWidth: CGFloat = 420
    @State private var dragStartChatPanelWidth: CGFloat?

    private let minChatPanelWidth: CGFloat = 300
    private let maxChatPanelWidth: CGFloat = 640

    var body: some View {
        HStack(spacing: 6) {
            ProjectSidebarView()
                .frame(width: 228)

            workbenchCard
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

            HStack(spacing: 0) {
                EditorAreaView()
                    .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)

                resizeHandle

                ChatPanelView()
                    .frame(width: chatPanelWidth)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(8)
        .background(AppTheme.editorSurface.opacity(0.86))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(AppTheme.hairline, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.055), radius: 16, y: 8)
    }

    private var resizeHandle: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 6)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if dragStartChatPanelWidth == nil {
                        dragStartChatPanelWidth = chatPanelWidth
                    }
                    let startWidth = dragStartChatPanelWidth ?? chatPanelWidth
                    chatPanelWidth = clampedChatPanelWidth(startWidth - value.translation.width)
                }
                .onEnded { _ in
                    dragStartChatPanelWidth = nil
                }
        )
        .help("拖动调整编辑器和聊天面板宽度")
    }

    private func clampedChatPanelWidth(_ width: CGFloat) -> CGFloat {
        min(max(width, minChatPanelWidth), maxChatPanelWidth)
    }
}
