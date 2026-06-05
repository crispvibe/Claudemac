import SwiftUI

struct LoginView: View {
    @ObservedObject var viewModel: AuthViewModel
    let showRegister: () -> Void
    let showForgot: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 16)
                    AuthHeaderView(title: "欢迎回来", subtitle: "登录 AnnaCode，继续连接你的远程工作区")

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
                            AuthSecureField(title: "密码", placeholder: "请输入密码", text: $viewModel.loginPassword)
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
                                Button("忘记密码") { showForgot() }
                                Spacer()
                                Button("创建账号") { showRegister() }
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.acodeInk)
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
