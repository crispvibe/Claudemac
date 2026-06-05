import SwiftUI

struct ForgotPasswordView: View {
    @ObservedObject var viewModel: AuthViewModel
    let showLogin: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 20) {
                    topBar
                    AuthHeaderView(title: "忘记密码", subtitle: "通过邮箱验证码重置登录密码")

                    AuthLiquidCard {
                        VStack(spacing: 14) {
                            AuthTextField(
                                title: "邮箱",
                                placeholder: "请输入注册邮箱",
                                systemImage: "envelope",
                                text: $viewModel.forgotEmail,
                                keyboardType: .emailAddress,
                                textContentType: .emailAddress
                            )
                            AuthCodeField(
                                title: "邮箱验证码",
                                code: $viewModel.forgotVerificationCode,
                                sending: viewModel.forgotCodeSending,
                                cooldown: viewModel.forgotCooldown
                            ) {
                                Task { await viewModel.requestForgotPasswordCode() }
                            }
                            AuthSecureField(title: "新密码", placeholder: "设置新的登录密码", text: $viewModel.forgotPassword)
                            AuthSecureField(title: "确认新密码", placeholder: "再次输入新密码", text: $viewModel.forgotConfirmPassword)
                            AuthMessageView(message: viewModel.forgotMessage)
                            AuthPrimaryButton(
                                title: "重置密码",
                                loading: viewModel.forgotSubmitting,
                                disabled: !viewModel.canSubmitForgotPassword
                            ) {
                                Task { await viewModel.requestPasswordReset() }
                            }
                        }
                        .padding(18)
                    }
                    .padding(.horizontal, 18)
                    Spacer(minLength: 12)
                }
                .frame(maxWidth: 430)
                .frame(maxWidth: .infinity, minHeight: max(0, proxy.size.height - 36))
                .padding(.vertical, 18)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var topBar: some View {
        HStack {
            Button {
                showLogin()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.acodeInk)
                    .frame(width: 44, height: 44)
                    .acodeAuthCircleGlass()
                    .overlay(Circle().stroke(Color.acodeAuthGlassStroke, lineWidth: 1))
            }
            .buttonStyle(.acodePress)
            Spacer()
        }
        .padding(.horizontal, 18)
    }
}
