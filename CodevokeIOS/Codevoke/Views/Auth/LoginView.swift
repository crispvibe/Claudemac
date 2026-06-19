import SwiftUI

struct LoginView: View {
    @ObservedObject var viewModel: AuthViewModel
    let showRegister: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 16)
                    AuthHeaderView(title: "欢迎回来", subtitle: "登录 Codevoke，继续连接你的远程工作区")

                    AuthLiquidCard {
                        VStack(spacing: 16) {
                            AuthTextField(
                                title: "邮箱",
                                placeholder: "请输入邮箱",
                                systemImage: "envelope",
                                text: $viewModel.loginEmail,
                                keyboardType: .emailAddress,
                                textContentType: .emailAddress
                            )
                            AuthCodeField(
                                title: "邮箱验证码",
                                code: $viewModel.loginVerificationCode,
                                sending: viewModel.loginCodeSending,
                                cooldown: viewModel.loginCooldown
                            ) {
                                Task { await viewModel.requestLoginCode() }
                            }
                            AuthAgreementRow(agreed: $viewModel.loginAgreed) { type in
                                viewModel.presentLegalDocument(type)
                            }
                            AuthMessageView(message: viewModel.loginMessage)
                            AuthPrimaryButton(
                                title: "登录",
                                loading: viewModel.loginSubmitting,
                                disabled: !viewModel.canSubmitLogin,
                                disabledKeepsBlack: true
                            ) {
                                Task { await viewModel.requestLogin() }
                            }

                            HStack {
                                Spacer()
                                Button("创建账号") { showRegister() }
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.codevokeInk)
                            .buttonStyle(.plain)
                        }
                        .padding(18)
                    }
                    .padding(.horizontal, 18)
                    Spacer(minLength: 10)
                    AppFooterView(footer: viewModel.appFooter)
                    Spacer(minLength: 16)
                }
                .frame(maxWidth: 430)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
