import SwiftUI

struct ForgotPasswordView: View {
    var onLogin: () -> Void = {}

    @EnvironmentObject private var accountAuth: AccountAuthViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("忘记密码")
                .font(.system(size: 18, weight: .semibold))

            AccountTextField(title: "邮箱", systemImage: "envelope", text: $accountAuth.forgotEmail)
            AccountTextField(
                title: "邮箱验证码",
                systemImage: "number",
                text: $accountAuth.forgotVerificationCode,
                trailingTitle: accountAuth.forgotCooldown > 0 ? "\(accountAuth.forgotCooldown)s" : (accountAuth.forgotCodeSending ? "发送中" : "获取"),
                trailingAction: { Task { await accountAuth.requestForgotPasswordCode() } },
                trailingDisabled: accountAuth.forgotCodeSending || accountAuth.forgotCooldown > 0
            )
            AccountSecureField(title: "新密码", systemImage: "lock", text: $accountAuth.forgotPassword)
            AccountSecureField(title: "确认新密码", systemImage: "lock.rotation", text: $accountAuth.forgotConfirmPassword)

            if let message = accountAuth.forgotMessage {
                AccountMessageView(message: message, severity: accountAuth.forgotMessageSeverity)
            }

            Button {
                Task { await accountAuth.requestPasswordReset() }
            } label: {
                Text(accountAuth.forgotSubmitting ? "重置中…" : "重置密码")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AccountPrimaryButtonStyle())
            .disabled(accountAuth.forgotSubmitting)

            Button(action: onLogin) {
                Text("返回登录")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AccountPrimaryButtonStyle())
        }
    }
}
