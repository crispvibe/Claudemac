import SwiftUI

struct RegisterView: View {
    @ObservedObject var viewModel: AuthViewModel
    let showLogin: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 20) {
                    topBar
                    AuthHeaderView(title: "创建账号", subtitle: "使用邮箱验证码完成账号创建")

                    AuthLiquidCard {
                        VStack(spacing: 14) {
                            AuthTextField(
                                title: "邮箱",
                                placeholder: "请输入邮箱",
                                systemImage: "envelope",
                                text: $viewModel.registerEmail,
                                keyboardType: .emailAddress,
                                textContentType: .emailAddress
                            )
                            AuthCodeField(
                                title: "邮箱验证码",
                                code: $viewModel.registerVerificationCode,
                                sending: viewModel.registerCodeSending,
                                cooldown: viewModel.registerCooldown
                            ) {
                                Task { await viewModel.requestRegisterCode() }
                            }
                            AuthSecureField(title: "密码", placeholder: "设置登录密码", text: $viewModel.registerPassword)
                            AuthSecureField(title: "确认密码", placeholder: "再次输入密码", text: $viewModel.registerConfirmPassword)
                            AuthAgreementRow(agreed: $viewModel.registerAgreed) { type in
                                viewModel.presentLegalDocument(type)
                            }
                            AuthMessageView(message: viewModel.registerMessage)
                            AuthPrimaryButton(
                                title: "注册并登录",
                                loading: viewModel.registerSubmitting,
                                disabled: !viewModel.canSubmitRegister
                            ) {
                                Task { await viewModel.requestRegister() }
                            }
                        }
                        .padding(18)
                    }
                    .padding(.horizontal, 18)
                    Spacer(minLength: 8)
                    AppFooterView(footer: viewModel.appFooter)
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
                    .foregroundStyle(Color.codevokeInk)
                    .frame(width: 44, height: 44)
                    .codevokeAuthCircleGlass()
                    .overlay(Circle().stroke(Color.codevokeAuthGlassStroke, lineWidth: 1))
            }
            .buttonStyle(.codevokePress)
            Spacer()
        }
        .padding(.horizontal, 18)
    }
}
