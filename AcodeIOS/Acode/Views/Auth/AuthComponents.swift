import SwiftUI
import UIKit

struct AuthHeaderView: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 12) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 66, height: 66)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(.white.opacity(0.7), lineWidth: 0.8)
                }

            VStack(spacing: 5) {
                Text(L10n.key(title))
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.codevokeInk)
                Text(L10n.key(subtitle))
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color.codevokeMuted)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

struct AuthLiquidCard<Content: View>: View {
    @ViewBuilder var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .codevokeAuthGlass(cornerRadius: 30)
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(Color.codevokeAuthGlassStroke, lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.06), radius: 22, x: 0, y: 12)
    }
}

struct AuthTextField: View {
    let title: String
    let placeholder: String
    let systemImage: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(L10n.key(title))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.codevokeMuted)
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.codevokeMuted)
                    .frame(width: 18)
                TextField(L10n.string(placeholder), text: $text)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.codevokeInk)
                    .keyboardType(keyboardType)
                    .textContentType(textContentType)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.codevokeAuthGlassStroke, lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.10), radius: 16, x: 0, y: 8)
        }
    }
}

struct AuthSecureField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    @State private var isSecured = true

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(L10n.key(title))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.codevokeMuted)
            HStack(spacing: 10) {
                Image(systemName: "lock")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.codevokeMuted)
                    .frame(width: 18)
                Group {
                    if isSecured {
                        SecureField(L10n.string(placeholder), text: $text)
                    } else {
                        TextField(L10n.string(placeholder), text: $text)
                    }
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.codevokeInk)
                .textContentType(.password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                Button {
                    isSecured.toggle()
                } label: {
                    Image(systemName: isSecured ? "eye" : "eye.slash")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.codevokeMuted)
                }
                .buttonStyle(.codevokePress)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.codevokeAuthGlassStroke, lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.10), radius: 16, x: 0, y: 8)
        }
    }
}

struct AuthCodeField: View {
    let title: String
    @Binding var code: String
    let sending: Bool
    let cooldown: Int
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(L10n.key(title))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.codevokeMuted)
            HStack(spacing: 10) {
                Image(systemName: "number")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.codevokeMuted)
                    .frame(width: 18)
                TextField(L10n.string("6 位验证码"), text: $code)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.codevokeInk)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                Button {
                    action()
                } label: {
                    Group {
                        if sending {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Text(cooldown > 0 ? "\(cooldown)s" : L10n.string("获取"))
                        }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(minWidth: 58, minHeight: 34)
                    .padding(.horizontal, 4)
                    .background(.white, in: Capsule())
                    .frame(minWidth: 66, minHeight: 44)
                }
                .buttonStyle(.codevokePress)
                .disabled(sending || cooldown > 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.codevokeAuthGlassStroke, lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.10), radius: 16, x: 0, y: 8)
        }
    }
}

struct AuthPrimaryButton: View {
    let title: String
    let loading: Bool
    let disabled: Bool
    var disabledKeepsBlack = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if loading {
                    ProgressView()
                        .tint(.white)
                        .controlSize(.small)
                }
                Text(L10n.key(title))
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white.opacity(disabled ? 0.72 : 1))
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .background(
                Color.black.opacity(disabled && !disabledKeepsBlack ? 0.55 : 1),
                in: RoundedRectangle(cornerRadius: 26, style: .continuous)
            )
        }
        .buttonStyle(.codevokePress)
        .disabled(disabled)
    }
}

struct AuthAgreementRow: View {
    @Binding var agreed: Bool
    let showDocument: (RemoteLegalDocumentType) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            agreementLayout(stackedText: false)
            agreementLayout(stackedText: true)
        }
    }

    private func agreementLayout(stackedText: Bool) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Button {
                agreed.toggle()
            } label: {
                Image(systemName: agreed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(agreed ? Color.codevokeInk : Color.codevokeMuted)
            }
            .buttonStyle(.codevokePress)
            .padding(.top, stackedText ? 1 : 0)

            if stackedText {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.key("我已阅读并同意"))
                        .foregroundStyle(Color.codevokeMuted)
                    HStack(spacing: 0) {
                        legalButton("用户协议", type: .userAgreement)
                        Text(L10n.key("和"))
                            .foregroundStyle(Color.codevokeMuted)
                        legalButton("隐私政策", type: .privacyPolicy)
                    }
                }
            } else {
                HStack(spacing: 0) {
                    Text(L10n.key("我已阅读并同意"))
                        .foregroundStyle(Color.codevokeMuted)
                    legalButton("用户协议", type: .userAgreement)
                    Text(L10n.key("和"))
                        .foregroundStyle(Color.codevokeMuted)
                    legalButton("隐私政策", type: .privacyPolicy)
                }
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 12, weight: .medium))
    }

    private func legalButton(_ title: String, type: RemoteLegalDocumentType) -> some View {
        Button(L10n.string(title)) {
            showDocument(type)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(Color.codevokeInk.opacity(0.82))
        .buttonStyle(.plain)
    }
}

struct AuthMessageView: View {
    let message: String?

    var body: some View {
        if let message, !message.isEmpty {
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(message.contains("已") ? Color.codevokeMuted : Color.red.opacity(0.92))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 2)
        }
    }
}

struct AppFooterView: View {
    let footer: RemoteAppFooter

    var body: some View {
        VStack(spacing: 5) {
            Text(footer.companyName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.codevokeInk.opacity(0.54))
            ForEach(Array(footer.displayLines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.codevokeMuted.opacity(0.72))
                    .multilineTextAlignment(.center)
            }
        }
        .lineLimit(2)
        .minimumScaleFactor(0.86)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
    }
}

struct LegalDocumentSheet: View {
    let document: RemoteLegalDocument

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(document.content)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.codevokeInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
            }
            .background(WhiteGlassBackground().ignoresSafeArea())
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
