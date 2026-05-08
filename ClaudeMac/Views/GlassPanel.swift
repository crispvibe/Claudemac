import AppKit
import SwiftUI

enum AppTheme {
    static let windowTint = Color.white.opacity(0.18)
    static let editorSurface = Color.white.opacity(0.84)
    static let panelSurface = Color.white.opacity(0.26)
    static let controlSurface = Color.white.opacity(0.40)
    static let selectedSurface = Color.accentColor.opacity(0.10)
    static let hairline = Color.black.opacity(0.06)
    static let weakHairline = Color.black.opacity(0.035)
}

struct GlassPanel<Content: View>: View {
    var material: NSVisualEffectView.Material = .sidebar
    var radius: CGFloat = 20
    var surfaceOpacity: Double = 0.62
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background {
                ZStack {
                    VisualEffectView(material: material, blendingMode: .withinWindow)
                        .opacity(surfaceOpacity)
                    AppTheme.panelSurface
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(AppTheme.weakHairline, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 18, y: 8)
    }
}

struct PrimaryGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: 38)
            .background(configuration.isPressed ? Color.white.opacity(0.20) : AppTheme.controlSurface)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(AppTheme.hairline, lineWidth: 1)
            )
    }
}
