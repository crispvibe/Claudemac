import SwiftUI

struct LoginView: View {
    var onRegister: () -> Void = {}

    @EnvironmentObject private var accountAuth: AccountAuthViewModel
    @FocusState private var focusedField: Field?

    private enum Field {
        case email
        case code
    }

    private var canSubmit: Bool {
        accountAuth.canSubmitLogin
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("登录")
                .font(.system(size: 18, weight: .semibold))

            AccountTextField(
                title: "邮箱",
                systemImage: "envelope",
                text: $accountAuth.loginEmail,
                isFocused: focusedField == .email
            )
            .focused($focusedField, equals: .email)
            .onSubmit {
                focusedField = .code
            }

            AccountTextField(
                title: "邮箱验证码",
                systemImage: "number",
                text: $accountAuth.loginVerificationCode,
                trailingTitle: accountAuth.loginCooldown > 0 ? "\(accountAuth.loginCooldown)s" : (accountAuth.loginCodeSending ? "发送中" : "获取"),
                trailingAction: { Task { await accountAuth.requestLoginCode() } },
                trailingDisabled: accountAuth.loginCodeSending || accountAuth.loginCooldown > 0,
                isFocused: focusedField == .code
            )
            .focused($focusedField, equals: .code)
            .onSubmit {
                guard canSubmit else { return }
                Task { await accountAuth.requestLogin() }
            }

            AccountAgreementRow(agreed: $accountAuth.loginAgreed) { type in
                accountAuth.presentLegalDocument(type)
            }

            if let message = accountAuth.loginMessage {
                AccountMessageView(message: message, severity: accountAuth.loginMessageSeverity)
            }
            if let message = accountAuth.documentMessage {
                AccountMessageView(message: message, severity: .error)
            }

            Button {
                Task { await accountAuth.requestLogin() }
            } label: {
                Text(accountAuth.loginSubmitting ? "登录中…" : "登录")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AccountPrimaryButtonStyle())
            .disabled(!canSubmit)

            HStack {
                Spacer()

                Button("注册账号", action: onRegister)
                    .buttonStyle(AccountInlineButtonStyle())
            }
            .padding(.top, 4)
        }
        .onAppear {
            focusedField = .email
        }
        .task {
            await accountAuth.loadLegalDocumentsIfNeeded()
        }
    }
}
