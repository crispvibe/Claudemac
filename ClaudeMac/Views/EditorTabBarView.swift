import SwiftUI

struct EditorTabBarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(appState.openTabs) { tab in
                        tabView(tab)
                    }
                    addTabButton
                }
                .padding(.horizontal, 0)
            }
        }
        .frame(height: 39)
    }

    private var addTabButton: some View {
        Button {
            appState.openExternalFiles()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .regular))
                .frame(width: 34, height: 35)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .padding(.bottom, 1)
    }

    private func tabView(_ tab: EditorTab) -> some View {
        let selected = appState.selectedTabID == tab.id

        return HStack(spacing: 10) {
            Text(tab.title + (tab.isDirty ? " •" : ""))
                .font(.system(size: 13, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? .primary : .secondary)
                .lineLimit(1)
                .frame(maxWidth: selected ? 136 : 118, alignment: .leading)

            Button {
                appState.closeTab(tab)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .medium))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary.opacity(selected ? 0.74 : 0.52))
        }
        .padding(.leading, selected ? 16 : 14)
        .padding(.trailing, selected ? 11 : 10)
        .frame(width: selected ? 186 : 160, height: selected ? 37 : 34)
        .background {
            if selected {
                TopRoundedTabShape(radius: 18)
                    .fill(Color.white)
            }
        }
        .overlay(alignment: .bottom) {
            if selected {
                Rectangle()
                    .fill(Color.white)
                    .frame(height: 2)
            }
        }
        .padding(.bottom, 0)
        .zIndex(selected ? 1 : 0)
        .contentShape(Rectangle())
        .onTapGesture { appState.selectTab(tab) }
    }
}

private struct TopRoundedTabShape: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(radius, rect.width / 2, rect.height)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + radius, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + radius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

