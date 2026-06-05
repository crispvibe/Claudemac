import Foundation

@MainActor
final class AuthViewModel: ObservableObject {
    enum GateState: Equatable {
        case checking
        case unauthenticated
        case authenticated
    }

    @Published private(set) var gateState: GateState = .checking
    @Published private(set) var currentSession: RemoteAuthSession?
    @Published private(set) var legalDocuments: [RemoteLegalDocumentType: RemoteLegalDocument] = [:]
    @Published private(set) var appFooter: RemoteAppFooter = .default
    @Published private(set) var legalDocumentsLoading = false
    @Published private(set) var loginCodeSending = false
    @Published private(set) var registerCodeSending = false
    @Published private(set) var forgotCodeSending = false
    @Published private(set) var loginSubmitting = false
    @Published private(set) var registerSubmitting = false
    @Published private(set) var forgotSubmitting = false
    @Published private(set) var loginCooldown = 0
    @Published private(set) var registerCooldown = 0
    @Published private(set) var forgotCooldown = 0
    @Published private(set) var selectedLegalDocument: RemoteLegalDocument?
    @Published var loginEmail = ""
    @Published var loginPassword = ""
    @Published var loginAgreed = false
    @Published var loginMessage: String?
    @Published var registerEmail = ""
    @Published var registerVerificationCode = ""
    @Published var registerPassword = ""
    @Published var registerConfirmPassword = ""
    @Published var registerAgreed = false
    @Published var registerMessage: String?
    @Published var forgotEmail = ""
    @Published var forgotVerificationCode = ""
    @Published var forgotPassword = ""
    @Published var forgotConfirmPassword = ""
    @Published var forgotMessage: String?
    @Published var changePasswordCurrent = ""
    @Published var changePasswordNew = ""
    @Published var changePasswordConfirm = ""
    @Published private(set) var changePasswordSubmitting = false
    @Published private(set) var accountDeletionSubmitting = false
    @Published var accountDeletionMessage: String?
    @Published private(set) var remoteDevices: [RemoteDevice] = []
    @Published private(set) var remoteDevicesLoading = false
    @Published private(set) var deviceCodeResolving = false
    @Published private(set) var remoteConnectionSubmitting = false
    @Published private(set) var resolvedDevice: RemoteDeviceResolveResponse?
    @Published var deviceCodeInput = ""
    @Published var remoteConnectionMessage: String?
    @Published var changePasswordMessage: String?
    @Published var documentMessage: String?

    private let authClient: RemoteAuthClient
    private let legalClient: RemoteLegalClient
    private let tokenStore: RemoteTokenStore
    private let identityStore: DeviceIdentityStore
    private let signalingClient: SignalingClient
    @Published private(set) var localDeviceId: Int?
    private var didBootstrap = false
    private var legalDocumentsTask: Task<Void, Never>?
    private var didLoadAppFooter = false
    private var registerCooldownTask: Task<Void, Never>?
    private var forgotCooldownTask: Task<Void, Never>?

    init(
        authClient: RemoteAuthClient = RemoteAuthClient(),
        legalClient: RemoteLegalClient = RemoteLegalClient(),
        tokenStore: RemoteTokenStore = .shared,
        identityStore: DeviceIdentityStore = .shared,
        signalingClient: SignalingClient? = nil
    ) {
        self.authClient = authClient
        self.legalClient = legalClient
        self.tokenStore = tokenStore
        self.identityStore = identityStore
        self.signalingClient = signalingClient ?? .shared
    }

    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true
#if DEBUG
        print("[AnnaCodeAuth] bootstrap start")
#endif

        do {
            if let session = try await tokenStore.load() {
#if DEBUG
                print("[AnnaCodeAuth] token loaded expired=\(session.isExpired)")
#endif
                if session.isExpired {
                    let refreshed = try await authClient.refresh(refreshToken: session.refreshToken)
                    try await tokenStore.save(refreshed)
                    currentSession = refreshed
#if DEBUG
                    print("[AnnaCodeAuth] token refreshed")
#endif
                } else {
                    currentSession = session
                }
                gateState = .authenticated
#if DEBUG
                print("[AnnaCodeAuth] gate authenticated")
#endif
                if let currentSession {
                    await bootstrapLocalDevice(session: currentSession)
                }
            } else {
                gateState = .unauthenticated
#if DEBUG
                print("[AnnaCodeAuth] no token; gate unauthenticated")
#endif
            }
        } catch {
#if DEBUG
            print("[AnnaCodeAuth] bootstrap failed: \(error.localizedDescription)")
#endif
            try? await tokenStore.clear()
            currentSession = nil
            gateState = .unauthenticated
        }
    }

    func loadLegalDocumentsIfNeeded() async {
        guard !legalDocumentsLoading, legalDocuments.isEmpty else { return }
        legalDocumentsLoading = true
        documentMessage = nil
        defer { legalDocumentsLoading = false }

        do {
            async let privacyPolicy = legalClient.fetchDocument(type: .privacyPolicy)
            async let userAgreement = legalClient.fetchDocument(type: .userAgreement)
            let docs = try await [privacyPolicy, userAgreement]
            var mapped: [RemoteLegalDocumentType: RemoteLegalDocument] = [:]
            for document in docs {
                if let type = RemoteLegalDocumentType(rawValue: document.type) {
                    mapped[type] = document
                }
            }
            legalDocuments = mapped
        } catch {
            documentMessage = authErrorMessage(error, fallback: "协议暂时无法加载。")
        }
    }

    func loadAppFooterIfNeeded() async {
        guard !didLoadAppFooter else { return }
        do {
            appFooter = try await legalClient.fetchAppFooter()
            didLoadAppFooter = true
        } catch {
            appFooter = .default
        }
    }

    func presentLegalDocument(_ type: RemoteLegalDocumentType) {
        selectedLegalDocument = legalDocuments[type]
        if selectedLegalDocument == nil {
            documentMessage = L10n.string("协议暂时无法加载。")
        }
    }

    func dismissLegalDocument() {
        selectedLegalDocument = nil
    }

    func requestLogin() async {
        let email = loginEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = loginPassword
        guard !email.isEmpty, !password.isEmpty else {
            loginMessage = L10n.string("请输入邮箱和密码。")
            return
        }
        guard loginAgreed else {
            loginMessage = L10n.string("请先勾选用户协议和隐私政策。")
            return
        }
        loginSubmitting = true
        loginMessage = nil
        defer { loginSubmitting = false }

        do {
            let session = try await authClient.login(email: email, password: password)
            try await persistSession(session)
            Task { [weak self] in
                await self?.submitLegalConsentsIfNeeded(for: session)
            }
        } catch {
            loginMessage = authErrorMessage(error, fallback: "账号不存在或密码错误。")
        }
    }

    func requestRegisterCode() async {
        let email = registerEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty else {
            registerMessage = L10n.string("请输入邮箱。")
            return
        }
        registerCodeSending = true
        registerMessage = nil
        defer { registerCodeSending = false }

        do {
            _ = try await authClient.requestRegisterCode(email: email)
            startCooldown(kind: .register, seconds: 60)
            registerMessage = L10n.string("验证码已发送。")
        } catch {
            registerMessage = error.localizedDescription
        }
    }

    func requestRegister() async {
        let email = registerEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = registerPassword
        let confirmation = registerConfirmPassword
        let code = registerVerificationCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty, !password.isEmpty, !code.isEmpty else {
            registerMessage = L10n.string("请完整填写邮箱、验证码和密码。")
            return
        }
        guard password == confirmation else {
            registerMessage = L10n.string("两次密码不一致。")
            return
        }
        guard registerAgreed else {
            registerMessage = L10n.string("请先勾选用户协议和隐私政策。")
            return
        }
        registerSubmitting = true
        registerMessage = nil
        defer { registerSubmitting = false }

        do {
            let session = try await authClient.register(email: email, password: password, verificationCode: code)
            try await persistSession(session)
            Task { [weak self] in
                await self?.submitLegalConsentsIfNeeded(for: session)
            }
        } catch {
            registerMessage = authErrorMessage(error, fallback: "账号创建失败，请检查邮箱。")
        }
    }

    func requestForgotPasswordCode() async {
        let email = forgotEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty else {
            forgotMessage = L10n.string("请输入邮箱。")
            return
        }
        forgotCodeSending = true
        forgotMessage = nil
        defer { forgotCodeSending = false }

        do {
            _ = try await authClient.requestPasswordResetCode(email: email)
            startCooldown(kind: .forgot, seconds: 60)
            forgotMessage = L10n.string("验证码已发送。")
        } catch {
            forgotMessage = error.localizedDescription
        }
    }

    func requestPasswordReset() async {
        let email = forgotEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = forgotPassword
        let confirmation = forgotConfirmPassword
        let code = forgotVerificationCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty, !password.isEmpty, !code.isEmpty else {
            forgotMessage = L10n.string("请完整填写邮箱、验证码和新密码。")
            return
        }
        guard password == confirmation else {
            forgotMessage = L10n.string("两次密码不一致。")
            return
        }
        forgotSubmitting = true
        forgotMessage = nil
        defer { forgotSubmitting = false }

        do {
            try await authClient.resetPassword(email: email, password: password, verificationCode: code)
            forgotMessage = L10n.string("密码已重置，请返回登录。")
            loginPassword = ""
            loginAgreed = false
        } catch {
            forgotMessage = error.localizedDescription
        }
    }

    func requestChangePassword() async {
        let current = changePasswordCurrent
        let newPassword = changePasswordNew
        let confirmation = changePasswordConfirm
        guard let session = currentSession else {
            changePasswordMessage = L10n.string("登录状态已失效，请重新登录。")
            await clearSession()
            return
        }
        guard !current.isEmpty, !newPassword.isEmpty else {
            changePasswordMessage = L10n.string("请填写当前密码和新密码。")
            return
        }
        guard newPassword == confirmation else {
            changePasswordMessage = L10n.string("两次密码不一致。")
            return
        }
        changePasswordSubmitting = true
        changePasswordMessage = nil
        defer { changePasswordSubmitting = false }

        do {
            try await authClient.changePassword(currentPassword: current, newPassword: newPassword, accessToken: session.accessToken)
            changePasswordCurrent = ""
            changePasswordNew = ""
            changePasswordConfirm = ""
            changePasswordMessage = L10n.string("密码已修改，请重新登录。")
            await clearSession()
        } catch {
            changePasswordMessage = authErrorMessage(error, fallback: "密码修改失败。")
        }
    }

    func requestAccountDeletion(confirmAccount: String, confirmDestroy: String, confirmWaiveRights: String, reason: String) async -> Bool {
        guard let session = currentSession else {
            accountDeletionMessage = L10n.string("登录状态已失效，请重新登录。")
            await clearSession()
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
            accountDeletionMessage = L10n.string("账号已注销。")
            await clearSession()
            return true
        } catch {
            accountDeletionMessage = authErrorMessage(error, fallback: "账号注销失败。")
            return false
        }
    }

    func loadRemoteDevices() async {
        guard let session = currentSession, !remoteDevicesLoading else { return }
        remoteDevicesLoading = true
        remoteConnectionMessage = nil
        defer { remoteDevicesLoading = false }

        do {
            remoteDevices = try await authClient.devices(accessToken: session.accessToken)
                .filter { $0.deviceType == "desktop" || $0.platform == "macos" }
        } catch {
            remoteConnectionMessage = authErrorMessage(error, fallback: "设备列表加载失败。")
        }
    }

    func resolveDeviceCode() async {
        guard let session = currentSession else { return }
        let code = deviceCodeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else {
            remoteConnectionMessage = L10n.string("请输入设备码。")
            return
        }
        deviceCodeResolving = true
        remoteConnectionMessage = nil
        defer { deviceCodeResolving = false }

        do {
            resolvedDevice = try await authClient.resolveDeviceCode(code, accessToken: session.accessToken)
            remoteConnectionMessage = L10n.format("已找到 %@。", resolvedDevice?.deviceName ?? L10n.string("目标设备"))
        } catch {
            resolvedDevice = nil
            remoteConnectionMessage = authErrorMessage(error, fallback: "设备码解析失败。")
        }
    }

    func connectRemoteDevice(_ deviceId: Int) async {
        guard let session = currentSession, !remoteConnectionSubmitting else { return }
        remoteConnectionSubmitting = true
        remoteConnectionMessage = nil
        defer { remoteConnectionSubmitting = false }

        do {
            let connection = try await authClient.connect(deviceId: deviceId, accessToken: session.accessToken)
            switch connection.status {
            case "accepted":
                remoteConnectionMessage = connection.reason.flatMap(userFacingReasonMessage) ?? L10n.string("连接已授权，等待通道建立。")
            case "pending":
                remoteConnectionMessage = L10n.string("连接请求已发送，请在电脑端允许。")
            default:
                remoteConnectionMessage = connection.reason.flatMap(userFacingReasonMessage) ?? RemoteUserFacingText.status(connection.status)
            }
        } catch {
            remoteConnectionMessage = authErrorMessage(error, fallback: "连接请求失败。")
        }
    }

    func refreshSessionIfNeeded() async {
        guard let session = currentSession else { return }
        do {
            let refreshed = try await authClient.refresh(refreshToken: session.refreshToken)
            try await tokenStore.save(refreshed)
            currentSession = refreshed
        } catch {
            try? await tokenStore.clear()
            currentSession = nil
            gateState = .unauthenticated
        }
    }

    func clearSession() async {
        signalingClient.stop()
        try? await tokenStore.clear()
        currentSession = nil
        localDeviceId = nil
        remoteDevices = []
        resolvedDevice = nil
        remoteConnectionMessage = nil
        gateState = .unauthenticated
    }

    private func persistSession(_ session: RemoteAuthSession) async throws {
        try await tokenStore.save(session)
        currentSession = session
        gateState = .authenticated
        await bootstrapLocalDevice(session: session)
    }

    private func bootstrapLocalDevice(session: RemoteAuthSession) async {
        do {
            let identity = try await identityStore.loadOrCreateIdentity()
            let request = RemoteDeviceRegisterRequest(
                deviceUid: identity.deviceUID,
                deviceType: "ios",
                platform: RemoteAPIConfig.platform,
                deviceName: identity.deviceName,
                devicePublicKey: identity.devicePublicKey,
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
            )
            let device = try await authClient.registerDevice(request: request, accessToken: session.accessToken)
            if identity.deviceID != device.id {
                try await identityStore.updateDeviceID(device.id)
            }
            localDeviceId = device.id
            signalingClient.start(accessToken: session.accessToken, deviceId: device.id)
        } catch {
            remoteConnectionMessage = authErrorMessage(error, fallback: "本机 iOS 设备注册失败。")
        }
    }

    private func userFacingReasonMessage(_ reason: String) -> String? {
        RemoteUserFacingText.reason(reason)
    }

    private func authErrorMessage(_ error: Error, fallback: String) -> String {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return L10n.string(fallback) }
        return RemoteUserFacingText.apiError(message, fallback: fallback)
    }

    private func submitLegalConsentsIfNeeded(for session: RemoteAuthSession) async {
        if legalDocuments.isEmpty {
            await loadLegalDocumentsIfNeeded()
        }
        guard !legalDocuments.isEmpty else { return }

        let token = session.accessToken
        for type in RemoteLegalDocumentType.allCases {
            guard let document = legalDocuments[type] else { continue }
            do {
                try await legalClient.consent(documentId: document.id, accessToken: token)
            } catch {
                documentMessage = authErrorMessage(error, fallback: "协议暂时无法加载。")
            }
        }
    }

    private enum CooldownKind {
        case register
        case forgot
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
        case .forgot:
            forgotCooldownTask?.cancel()
            forgotCooldown = seconds
            forgotCooldownTask = Task { [weak self] in
                guard let self else { return }
                while !Task.isCancelled && self.forgotCooldown > 0 {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    guard !Task.isCancelled else { break }
                    await MainActor.run {
                        self.forgotCooldown -= 1
                    }
                }
            }
        }
    }

    var canSubmitLogin: Bool {
        !loginSubmitting && !loginEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !loginPassword.isEmpty && loginAgreed
    }

    var canSubmitRegister: Bool {
        !registerSubmitting && !registerEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !registerVerificationCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !registerPassword.isEmpty && registerPassword == registerConfirmPassword && registerAgreed
    }

    var canSubmitForgotPassword: Bool {
        !forgotSubmitting && !forgotEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !forgotPassword.isEmpty && forgotPassword == forgotConfirmPassword && !forgotVerificationCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canSubmitChangePassword: Bool {
        !changePasswordSubmitting && !changePasswordCurrent.isEmpty && !changePasswordNew.isEmpty && changePasswordNew == changePasswordConfirm
    }
}
