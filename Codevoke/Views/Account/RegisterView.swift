import SwiftUI

struct RegisterView: View {
    var onLogin: () -> Void = {}

    @EnvironmentObject private var accountAuth: AccountAuthViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("注册账号")
                .font(.system(size: 18, weight: .semibold))

            AccountTextField(title: "邮箱", systemImage: "envelope", text: $accountAuth.registerEmail)
            AccountTextField(
                title: "邮箱验证码",
                systemImage: "number",
                text: $accountAuth.registerVerificationCode,
                trailingTitle: accountAuth.registerCooldown > 0 ? "\(accountAuth.registerCooldown)s" : (accountAuth.registerCodeSending ? "发送中" : "获取"),
                trailingAction: { Task { await accountAuth.requestRegisterCode() } },
                trailingDisabled: accountAuth.registerCodeSending || accountAuth.registerCooldown > 0
            )
            AccountAgreementRow(agreed: $accountAuth.registerAgreed) { type in
                accountAuth.presentLegalDocument(type)
            }

            if let message = accountAuth.registerMessage {
                AccountMessageView(message: message, severity: accountAuth.registerMessageSeverity)
            }
            if let message = accountAuth.documentMessage {
                AccountMessageView(message: message, severity: .error)
            }

            Button {
                Task { await accountAuth.requestRegister() }
            } label: {
                Text(accountAuth.registerSubmitting ? "创建中…" : "创建账号")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AccountPrimaryButtonStyle())
            .disabled(!accountAuth.canSubmitRegister)

            Button("返回登录", action: onLogin)
                .buttonStyle(AccountInlineButtonStyle())
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 4)
        }
        .task {
            await accountAuth.loadLegalDocumentsIfNeeded()
        }
    }
}
