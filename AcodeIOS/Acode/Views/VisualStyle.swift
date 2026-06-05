import SwiftUI
import UIKit

extension Color {
    static let acodeInk = Color(red: 0.08, green: 0.08, blue: 0.08)
    static let acodeMuted = Color(red: 0.42, green: 0.42, blue: 0.42)
    static let acodeLine = Color.black.opacity(0.08)
    static let acodePanel = Color.white.opacity(0.72)
    static let acodeSoft = Color(red: 0.96, green: 0.96, blue: 0.95)
    static let acodeGlassFill = Color.white.opacity(0.52)
    static let acodeGlassStroke = Color.white.opacity(0.74)
    static let acodeHairline = Color.black.opacity(0.055)
    static let acodeAuthGlassFill = Color.white.opacity(0.68)
    static let acodeAuthGlassStroke = Color.white.opacity(0.88)
}

extension Animation {
    static func acodeSmooth(duration: TimeInterval) -> Animation {
        if #available(iOS 17.0, *) {
            return .smooth(duration: duration)
        }
        return .easeInOut(duration: duration)
    }
}

extension View {
    @ViewBuilder
    func acodeGlass(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .background(Color.acodeGlassFill, in: shape)
        }
    }

    @ViewBuilder
    func acodeCircleGlass() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: Circle())
        } else {
            self
                .background(.ultraThinMaterial, in: Circle())
                .background(Color.acodeGlassFill, in: Circle())
        }
    }

    @ViewBuilder
    func acodeAuthGlass(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .background(Color.acodeAuthGlassFill, in: shape)
        }
    }

    @ViewBuilder
    func acodeAuthCircleGlass() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: Circle())
        } else {
            self
                .background(.ultraThinMaterial, in: Circle())
                .background(Color.acodeAuthGlassFill, in: Circle())
        }
    }

    @ViewBuilder
    func acodePresentationCornerRadius(_ radius: CGFloat) -> some View {
        if #available(iOS 16.4, *) {
            self.presentationCornerRadius(radius)
        } else {
            self
        }
    }

    @ViewBuilder
    func acodeOnChange<Value: Equatable>(
        of value: Value,
        perform action: @escaping (_ oldValue: Value, _ newValue: Value) -> Void
    ) -> some View {
        if #available(iOS 17.0, *) {
            self.onChange(of: value) { oldValue, newValue in
                action(oldValue, newValue)
            }
        } else {
            self.onChange(of: value) { newValue in
                action(value, newValue)
            }
        }
    }
}

extension ToolbarItemPlacement {
    static var acodeTopBarLeading: ToolbarItemPlacement {
        if #available(iOS 17.0, *) {
            return .topBarLeading
        }
        return .navigationBarLeading
    }

    static var acodeTopBarTrailing: ToolbarItemPlacement {
        if #available(iOS 17.0, *) {
            return .topBarTrailing
        }
        return .navigationBarTrailing
    }
}

struct AnnaCodePressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .brightness(configuration.isPressed ? -0.025 : 0)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.acodeSmooth(duration: 0.16), value: configuration.isPressed)
    }
}

struct AnnaCodeBottomRoundedRectangle: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let clampedRadius = min(radius, rect.width / 2, rect.height / 2)
        let bezierPath = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: [.bottomLeft, .bottomRight],
            cornerRadii: CGSize(width: clampedRadius, height: clampedRadius)
        )
        return Path(bezierPath.cgPath)
    }
}

extension ButtonStyle where Self == AnnaCodePressButtonStyle {
    static var acodePress: AnnaCodePressButtonStyle { AnnaCodePressButtonStyle() }
}

struct GlassCard<Content: View>: View {
    let cornerRadius: CGFloat
    @ViewBuilder var content: Content

    init(cornerRadius: CGFloat = 28, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(.ultraThinMaterial, in: shape)
            .background(Color.white.opacity(0.82), in: shape)
            .overlay {
                shape
                    .stroke(Color.white.opacity(0.82), lineWidth: 1)
            }
            .overlay {
                shape
                    .stroke(Color.black.opacity(0.045), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.06), radius: 18, x: 0, y: 10)
    }
}

struct WhiteGlassBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                .white,
                Color(red: 0.992, green: 0.992, blue: 0.988),
                Color(red: 0.975, green: 0.976, blue: 0.972)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .topLeading) {
            Circle()
                .fill(.white.opacity(0.98))
                .frame(width: 240, height: 240)
                .blur(radius: 34)
                .offset(x: -70, y: -80)
        }
    }
}
