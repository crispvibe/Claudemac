import SwiftUI

struct AppRootView: View {
    @StateObject private var authViewModel = AuthViewModel()
    @State private var didBootstrap = false

    var body: some View {
        Group {
            switch authViewModel.gateState {
            case .checking:
                ZStack {
                    WhiteGlassBackground()
                        .ignoresSafeArea()
                    ProgressView()
                        .tint(.black)
                        .scaleEffect(1.1)
                }
            case .unauthenticated:
                AuthRootView(viewModel: authViewModel)
            case .authenticated:
                RootView(authViewModel: authViewModel)
            }
        }
        .task {
            guard !didBootstrap else { return }
            didBootstrap = true
            await authViewModel.bootstrap()
        }
    }
}
