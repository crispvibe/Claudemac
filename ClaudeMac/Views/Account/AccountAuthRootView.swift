import AppKit
import SwiftUI

struct AccountAuthRootView: View {
    private enum Mode {
        case login
        case register
        case forgot
    }

    @EnvironmentObject private var accountAuth: AccountAuthViewModel
    @State private var mode: Mode = .login

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            accountBrand
            authContent
        }
        .sheet(item: legalDocumentBinding) { document in
            LegalDocumentSheet(document: document)
        }
    }

    private var accountBrand: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 44, height: 44)
                .background(AppTheme.secondaryCardSurface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppTheme.hairline, lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text("Codevoke")
                    .font(.system(size: 15, weight: .semibold))
                Text("登录以继续你的远程开发工作")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var authContent: some View {
        switch mode {
        case .login:
            LoginView(
                onRegister: { setMode(.register) },
                onForgotPassword: { setMode(.forgot) }
            )
        case .register:
            RegisterView(onLogin: { setMode(.login) })
        case .forgot:
            ForgotPasswordView(onLogin: { setMode(.login) })
        }
    }

    private func setMode(_ nextMode: Mode) {
        withAnimation(.easeOut(duration: 0.16)) {
            mode = nextMode
        }
    }

    private var legalDocumentBinding: Binding<RemoteLegalDocument?> {
        Binding(
            get: { accountAuth.selectedLegalDocument },
            set: { _ in accountAuth.dismissLegalDocument() }
        )
    }
}
