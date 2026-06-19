import Foundation

@MainActor
final class AccountAuthViewModel: ObservableObject {
    enum GateState: Equatable {
        case checking
        case unauthenticated
        case authenticated
    }

    private enum SubscriptionLoadResult {
        case loaded
        case transientFailure
        case unauthorized
    }

    @Published private(set) var gateState: GateState = .checking
    @Published private(set) var currentSession: RemoteAuthSession?
    @Published private(set) var loginSubmitting = false
    @Published private(set) var loginCodeSending = false
    @Published private(set) var loginCooldown = 0
    @Published private(set) var registerCodeSending = false
    @Published private(set) var registerSubmitting = false
    @Published private(set) var registerCooldown = 0
    @Published private(set) var subscription: RemoteSubscription?
    @Published private(set) var subscriptionLoading = false
    @Published private(set) var subscriptionPlans: [RemoteSubscriptionPlan] = []
    @Published private(set) var subscriptionPlansLoading = false
    @Published private(set) var subscriptionOrderCreating = false
    @Published private(set) var legalDocuments: [RemoteLegalDocumentType: RemoteLegalDocument] = [:]
    @Published private(set) var legalDocumentsLoading = false
    @Published private(set) var selectedLegalDocument: RemoteLegalDocument?
    @Published private(set) var accountDeletionSubmitting = false
    @Published var subscriptionMessage: String?
    @Published var loginEmail = ""
    @Published var loginVerificationCode = ""
    @Published var loginAgreed = false
    @Published var loginMessage: String?
    @Published var loginMessageSeverity: AccountMessageSeverity = .error
    @Published var registerEmail = ""
    @Published var registerVerificationCode = ""
    @Published var registerAgreed = false
    @Published var registerMessage: String?
    @Published var registerMessageSeverity: AccountMessageSeverity = .error
    @Published var accountDeletionMessage: String?
    @Published var documentMessage: String?

    private let authClient: AccountAuthClient
    private let tokenStore: AccountTokenStore
    private let deviceProvisioning: DeviceProvisioningViewModel
    private var didBootstrap = false
    private var registerCooldownTask: Task<Void, Never>?
    private var loginCooldownTask: Task<Void, Never>?

    init(
        authClient: AccountAuthClient = AccountAuthClient(),
        tokenStore: AccountTokenStore = .shared,
        deviceProvisioning: DeviceProvisioningViewModel
    ) {
        self.authClient = authClient
        self.tokenStore = tokenStore
        self.deviceProvisioning = deviceProvisioning
    }

    var maskedAccount: String {
        currentSession.map { accountRemoteDisplayAccount($0.user) } ?? ""
    }

    var canSubmitLogin: Bool {
        !loginSubmitting
            && !loginEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !loginVerificationCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && loginAgreed
    }

    var canSubmitRegister: Bool {
        !registerSubmitting
            && !registerEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !registerVerificationCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && registerAgreed
    }

    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true

        do {
            guard let session = try await tokenStore.load() else {
                currentSession = nil
                gateState = .unauthenticated
                return
            }

            let activeSession: RemoteAuthSession
            if session.isExpired {
                do {
                    activeSession = try await authClient.refresh(refreshToken: session.refreshToken)
                    try await tokenStore.save(activeSession)
                } catch {
                    try? await tokenStore.clear()
                    currentSession = nil
                    gateState = .unauthenticated
                    loginMessage = nil
                    return
                }
            } else {
                activeSession = session
            }

            currentSession = activeSession
            gateState = .authenticated
            if await loadSubscription(session: activeSession) == .unauthorized {
                await expireStoredSession(message: "登录状态已失效，请重新登录。")
                return
            }
            await deviceProvisioning.bootstrap(session: activeSession)
        } catch {
            currentSession = nil
            gateState = .unauthenticated
            try? await tokenStore.clear()
            await deviceProvisioning.clearForLogout()
            loginMessage = nil
        }
    }

    func requestLoginCode() async {
        let email = normalizedEmail(loginEmail)
        guard !email.isEmpty else {
            loginMessageSeverity = .error
            loginMessage = "请输入邮箱。"
            return
        }
        guard isValidEmail(email) else {
            loginMessageSeverity = .error
            loginMessage = "请输入正确的邮箱地址。"
            return
        }
        loginCodeSending = true
        loginMessage = nil
        defer { loginCodeSending = false }

        do {
            _ = try await authClient.requestLoginCode(email: email)
            startCooldown(kind: .login, seconds: 60)
            loginMessageSeverity = .success
            loginMessage = "验证码已发送。"
        } catch {
            loginMessageSeverity = .error
            loginMessage = authErrorMessage(error, fallback: "验证码发送失败，请稍后重试。")
        }
    }

    func requestLogin() async {
        let email = normalizedEmail(loginEmail)
        let code = loginVerificationCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty, !code.isEmpty else {
            loginMessageSeverity = .error
            loginMessage = "请输入邮箱和验证码。"
            return
        }
        guard loginAgreed else {
            loginMessageSeverity = .error
            loginMessage = "请先勾选用户协议和隐私政策。"
            return
        }
        guard isValidEmail(email) else {
            loginMessageSeverity = .error
            loginMessage = "请输入正确的邮箱地址。"
            return
        }
        loginSubmitting = true
        loginMessage = nil
        defer { loginSubmitting = false }

        do {
            let session = try await authClient.login(email: email, verificationCode: code)
            try await persistSession(session)
            loginMessageSeverity = .success
            loginMessage = "登录成功。"
        } catch let error as AccountTokenStoreError {
            loginMessageSeverity = .error
            loginMessage = AccountRemoteUserFacingText.apiError(error.localizedDescription, fallback: "登录成功，但本机保存登录状态失败，请检查本机存储权限后重试。")
        } catch {
            loginMessageSeverity = .error
            loginMessage = loginErrorMessage(error)
        }
    }

    func requestRegister() async {
        let email = normalizedEmail(registerEmail)
        let code = registerVerificationCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty, !code.isEmpty else {
            registerMessageSeverity = .error
            registerMessage = "请填写邮箱和验证码。"
            return
        }
        guard isValidEmail(email) else {
            registerMessageSeverity = .error
            registerMessage = "请输入正确的邮箱地址。"
            return
        }
        guard registerAgreed else {
            registerMessageSeverity = .error
            registerMessage = "请先勾选用户协议和隐私政策。"
            return
        }
        registerSubmitting = true
        registerMessage = nil
        defer { registerSubmitting = false }

        do {
            let session = try await authClient.register(email: email, verificationCode: code)
            try await persistSession(session)
        } catch {
            registerMessageSeverity = .error
            registerMessage = authErrorMessage(error, fallback: "账号创建失败，请检查邮箱。")
        }
    }

    func requestRegisterCode() async {
        let email = normalizedEmail(registerEmail)
        guard !email.isEmpty else {
            registerMessageSeverity = .error
            registerMessage = "请输入邮箱。"
            return
        }
        guard isValidEmail(email) else {
            registerMessageSeverity = .error
            registerMessage = "请输入正确的邮箱地址。"
            return
        }
        registerCodeSending = true
        registerMessage = nil
        defer { registerCodeSending = false }

        do {
            _ = try await authClient.requestRegisterCode(email: email)
            startCooldown(kind: .register, seconds: 60)
            registerMessageSeverity = .success
            registerMessage = "验证码已发送。"
        } catch {
            registerMessageSeverity = .error
            registerMessage = authErrorMessage(error, fallback: "验证码发送失败，请稍后重试。")
        }
    }

    func logout() async {
        if let session = currentSession {
            try? await authClient.logout(accessToken: session.accessToken)
        }
        await clearLocalSession()
    }

    func loadLegalDocumentsIfNeeded() async {
        guard !legalDocumentsLoading, legalDocuments.isEmpty else { return }
        legalDocumentsLoading = true
        documentMessage = nil
        defer { legalDocumentsLoading = false }

        do {
            async let privacyPolicy = authClient.legalDocument(type: .privacyPolicy)
            async let userAgreement = authClient.legalDocument(type: .userAgreement)
            let documents = try await [privacyPolicy, userAgreement]
            var mapped: [RemoteLegalDocumentType: RemoteLegalDocument] = [:]
            for document in documents {
                if let type = RemoteLegalDocumentType(rawValue: document.type) {
                    mapped[type] = document
                }
            }
            legalDocuments = mapped
        } catch {
            documentMessage = authErrorMessage(error, fallback: "协议暂时无法加载。")
        }
    }

    func presentLegalDocument(_ type: RemoteLegalDocumentType) {
        selectedLegalDocument = legalDocuments[type]
        if selectedLegalDocument == nil {
            documentMessage = "协议暂时无法加载。"
        }
    }

    func dismissLegalDocument() {
        selectedLegalDocument = nil
    }

    func requestAccountDeletion(confirmAccount: String, confirmDestroy: String, confirmWaiveRights: String, reason: String) async -> Bool {
        guard let session = currentSession else {
            accountDeletionMessage = "登录状态已失效，请重新登录。"
            await clearLocalSession()
            return false
        }
        accountDeletionSubmitting = true
        accountDeletionMessage = nil
        defer { accountDeletionSubmitting = false }

        do {
            _ = try await authClient.deleteAccount(
                confirmAccount: confirmAccount,
                confirmDestroy: confirmDestroy,
                confirmWaiveRights: confirmWaiveRights,
                reason: reason,
                accessToken: session.accessToken
            )
            accountDeletionMessage = "账号已注销。"
            await clearLocalSession(resetProvisionedDevice: true)
            return true
        } catch {
            accountDeletionMessage = authErrorMessage(error, fallback: "账号注销失败。")
            return false
        }
    }

    private func clearLocalSession(resetProvisionedDevice: Bool = false) async {
        try? await tokenStore.clear()
        await deviceProvisioning.clearForLogout(resetProvisionedDevice: resetProvisionedDevice)
        subscription = nil
        subscriptionPlans = []
        subscriptionMessage = nil
        currentSession = nil
        gateState = .unauthenticated
        clearSensitiveAuthFields()
    }

    private func persistSession(_ session: RemoteAuthSession) async throws {
        currentSession = session
        gateState = .authenticated
        loginEmail = session.user.displayAccount
        registerEmail = session.user.displayAccount
        clearSensitiveAuthFields()
        try await tokenStore.save(session)
        loginMessage = nil
        registerMessage = nil
        await submitLegalConsentsIfNeeded(for: session)
        if await loadSubscription(session: session) == .unauthorized {
            await expireStoredSession(message: "登录状态已失效，请重新登录。")
            return
        }
        await deviceProvisioning.bootstrap(session: session)
    }

    func loadSubscription() async {
        guard let session = currentSession else { return }
        if await loadSubscription(session: session) == .unauthorized {
            await expireStoredSession(message: "登录状态已失效，请重新登录。")
        }
    }

    func loadSubscriptionPlans() async {
        guard let session = currentSession, !subscriptionPlansLoading else { return }
        subscriptionPlansLoading = true
        subscriptionMessage = nil
        defer { subscriptionPlansLoading = false }
        do {
            subscriptionPlans = try await authClient.subscriptionPlans(accessToken: session.accessToken)
        } catch {
            subscriptionMessage = authErrorMessage(error, fallback: "电脑端服务权益暂时无法加载。")
        }
    }

    func createSubscriptionOrder(plan: RemoteSubscriptionPlan) async -> URL? {
        guard let session = currentSession, !subscriptionOrderCreating else { return nil }
        subscriptionOrderCreating = true
        subscriptionMessage = nil
        defer { subscriptionOrderCreating = false }
        do {
            let order = try await authClient.createSubscriptionOrder(planCode: plan.code, accessToken: session.accessToken)
            guard let payUrl = order.payUrl, let url = URL(string: payUrl) else {
                subscriptionMessage = "服务开通流程已启动，但页面没有返回，请稍后刷新服务状态。"
                return nil
            }
            subscriptionMessage = "服务开通流程已启动，请在打开的页面继续完成。"
            return url
        } catch {
            subscriptionMessage = authErrorMessage(error, fallback: "服务开通流程创建失败。")
            return nil
        }
    }

    @discardableResult
    private func loadSubscription(session: RemoteAuthSession) async -> SubscriptionLoadResult {
        guard !subscriptionLoading else { return .transientFailure }
        subscriptionLoading = true
        subscriptionMessage = nil
        defer { subscriptionLoading = false }
        do {
            subscription = try await authClient.subscription(accessToken: session.accessToken)
            return .loaded
        } catch let error as AccountAPIError {
            if case .unauthorized = error {
                subscriptionMessage = "登录状态已失效，请重新登录。"
                return .unauthorized
            }
            subscriptionMessage = "服务状态暂时无法加载。"
            return .transientFailure
        } catch {
            subscriptionMessage = "服务状态暂时无法加载。"
            return .transientFailure
        }
    }

    private func expireStoredSession(message: String) async {
        try? await tokenStore.clear()
        await deviceProvisioning.clearForLogout()
        subscription = nil
        subscriptionPlans = []
        currentSession = nil
        gateState = .unauthenticated
        loginMessageSeverity = .error
        loginMessage = message
    }

    private func clearSensitiveAuthFields() {
        loginVerificationCode = ""
        loginAgreed = false
        registerVerificationCode = ""
        registerAgreed = false
    }

    private func submitLegalConsentsIfNeeded(for session: RemoteAuthSession) async {
        if legalDocuments.isEmpty {
            await loadLegalDocumentsIfNeeded()
        }
        guard !legalDocuments.isEmpty else { return }
        for type in RemoteLegalDocumentType.allCases {
            guard let document = legalDocuments[type] else { continue }
            do {
                try await authClient.consentLegal(documentId: document.id, accessToken: session.accessToken)
            } catch {
                documentMessage = authErrorMessage(error, fallback: "协议确认记录提交失败。")
            }
        }
    }

    private enum CooldownKind {
        case register
        case login
    }

    private func startCooldown(kind: CooldownKind, seconds: Int) {
        switch kind {
        case .register:
            registerCooldownTask?.cancel()
            registerCooldown = seconds
            registerCooldownTask = Task { [weak self] in
                guard let self else { return }
                while !Task.isCancelled && self.registerCooldown > 0 {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    guard !Task.isCancelled else { break }
                    await MainActor.run {
                        self.registerCooldown -= 1
                    }
                }
            }
        case .login:
            loginCooldownTask?.cancel()
            loginCooldown = seconds
            loginCooldownTask = Task { [weak self] in
                guard let self else { return }
                while !Task.isCancelled && self.loginCooldown > 0 {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    guard !Task.isCancelled else { break }
                    await MainActor.run {
                        self.loginCooldown -= 1
                    }
                }
            }
        }
    }

    private func authErrorMessage(_ error: Error, fallback: String) -> String {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return fallback }
        return AccountRemoteUserFacingText.apiError(message, fallback: fallback)
    }

    private func loginErrorMessage(_ error: Error) -> String {
        let fallback = "登录失败，请检查邮箱和验证码。"
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return fallback }
        return AccountRemoteUserFacingText.loginError(message, fallback: fallback)
    }

    private func normalizedEmail(_ rawValue: String) -> String {
        rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func isValidEmail(_ email: String) -> Bool {
        email.range(of: #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

}
