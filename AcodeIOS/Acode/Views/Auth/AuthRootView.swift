import SwiftUI

struct AuthRootView: View {
    @ObservedObject var viewModel: AuthViewModel
    @State private var screen: AuthScreen = .login

    var body: some View {
        ZStack {
            WhiteGlassBackground()
                .ignoresSafeArea()

            Group {
                switch screen {
                case .login:
                    LoginView(
                        viewModel: viewModel,
                        showRegister: { screen = .register },
                        showForgot: { screen = .forgot }
                    )
                case .register:
                    RegisterView(
                        viewModel: viewModel,
                        showLogin: { screen = .login }
                    )
                case .forgot:
                    ForgotPasswordView(
                        viewModel: viewModel,
                        showLogin: { screen = .login }
                    )
                }
            }
            .transition(.opacity)
        }
        .animation(.codevokeSmooth(duration: 0.2), value: screen)
        .task {
            async let legalDocuments: Void = viewModel.loadLegalDocumentsIfNeeded()
            async let appFooter: Void = viewModel.loadAppFooterIfNeeded()
            _ = await (legalDocuments, appFooter)
        }
        .sheet(item: legalDocumentBinding) { document in
            LegalDocumentSheet(document: document)
                .codevokePresentationCornerRadius(28)
        }
    }

    private var legalDocumentBinding: Binding<RemoteLegalDocument?> {
        Binding(
            get: { viewModel.selectedLegalDocument },
            set: { _ in viewModel.dismissLegalDocument() }
        )
    }
}

private enum AuthScreen {
    case login
    case register
    case forgot
}
