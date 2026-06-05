import SwiftUI

struct AccountTextField: View {
    var title: String
    var systemImage: String
    @Binding var text: String
    var trailingTitle: String?
    var trailingAction: (() -> Void)?
    var trailingDisabled = false
    var isFocused = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: 16)

            TextField(title, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .textContentType(textContentType)

            if let trailingTitle, let trailingAction {
                Button(trailingTitle, action: trailingAction)
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .disabled(trailingDisabled)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(AppTheme.inputSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isFocused ? Color.accentColor : AppTheme.hairline, lineWidth: isFocused ? 1.4 : 1)
        }
        .shadow(color: isFocused ? Color.accentColor.opacity(0.20) : Color.clear, radius: 8, y: 2)
    }

    private var textContentType: NSTextContentType? {
        systemImage == "envelope" ? .emailAddress : nil
    }
}

struct AccountSecureField: View {
    var title: String
    var systemImage: String
    @Binding var text: String
    var isFocused = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: 16)

            SecureField(title, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(AppTheme.inputSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isFocused ? Color.accentColor : AppTheme.hairline, lineWidth: isFocused ? 1.4 : 1)
        }
        .shadow(color: isFocused ? Color.accentColor.opacity(0.20) : Color.clear, radius: 8, y: 2)
    }
}

struct AccountMessageView: View {
    var message: String
    var severity: AccountMessageSeverity

    var body: some View {
        Text(message)
            .font(.system(size: 12))
            .foregroundStyle(foregroundStyle)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var foregroundStyle: Color {
        switch severity {
        case .info, .success:
            .secondary
        case .error:
            Color.red.opacity(0.85)
        }
    }
}

struct AccountAgreementRow: View {
    @Binding var agreed: Bool
    var showDocument: (RemoteLegalDocumentType) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button {
                agreed.toggle()
            } label: {
                Image(systemName: agreed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(agreed ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(agreed ? "取消同意" : "同意协议")

            HStack(spacing: 0) {
                Text("我已阅读并同意")
                    .foregroundStyle(.secondary)
                legalButton("用户协议", type: .userAgreement)
                Text("和")
                    .foregroundStyle(.secondary)
                legalButton("隐私政策", type: .privacyPolicy)
            }
            .font(.system(size: 12, weight: .medium))

            Spacer(minLength: 0)
        }
    }

    private func legalButton(_ title: String, type: RemoteLegalDocumentType) -> some View {
        Button(title) {
            showDocument(type)
        }
        .buttonStyle(.plain)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(Color.primary.opacity(0.82))
    }
}

struct LegalDocumentSheet: View {
    let document: RemoteLegalDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(document.title)
                    .font(.system(size: 18, weight: .semibold))
                Text("版本 \(document.version)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                Text(document.content)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .frame(minHeight: 420)
            .background(AppTheme.inputSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AppTheme.hairline, lineWidth: 1))
		}
		.padding(24)
		.frame(width: 680)
		.frame(minHeight: 560)
		.background(AppTheme.cardSurface)
	}
}

struct AccountPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(isEnabled ? .white : .secondary)
            .padding(.horizontal, 14)
            .frame(minHeight: 42)
            .background {
                if isEnabled {
                    configuration.isPressed ? Color.black.opacity(0.78) : Color.black.opacity(0.90)
                } else {
                    AppTheme.buttonSurface
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay {
                if !isEnabled {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(AppTheme.hairline, lineWidth: 1)
                }
            }
    }
}

struct AccountSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .background(configuration.isPressed ? AppTheme.buttonPressedSurface : AppTheme.buttonSurface)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(AppTheme.hairline, lineWidth: 1)
            }
    }
}

struct AccountInlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(configuration.isPressed ? Color.primary.opacity(0.72) : Color.secondary)
            .contentShape(Rectangle())
    }
}
