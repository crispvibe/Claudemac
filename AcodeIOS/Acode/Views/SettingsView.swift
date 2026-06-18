import SwiftUI
import UIKit

private struct SettingsHomeSnapshot: Equatable {
    var accountSubtitle: String
    var connectionStatus: String
    var selectedCLI: String

    @MainActor
    init(chatViewModel: ChatViewModel, authViewModel: AuthViewModel) {
        accountSubtitle = authViewModel.currentSession?.user.displayAccount ?? L10n.string("已登录")
        connectionStatus = chatViewModel.effectiveConnectionStatus
        selectedCLI = chatViewModel.selectedCLI
    }
}

private enum SettingsRoute: Hashable {
    case account
    case legal
    case connection
    case cli
    case changePassword
    case accountDeletion
    case appUpdate
}

struct SettingsView: View {
    let chatViewModel: ChatViewModel
    @ObservedObject var authViewModel: AuthViewModel
    let close: () -> Void
    @State private var navigationPath: [SettingsRoute] = []
    @State private var homeSnapshot: SettingsHomeSnapshot

    init(chatViewModel: ChatViewModel, authViewModel: AuthViewModel, close: @escaping () -> Void) {
        self.chatViewModel = chatViewModel
        self._authViewModel = ObservedObject(wrappedValue: authViewModel)
        self.close = close
        _homeSnapshot = State(initialValue: SettingsHomeSnapshot(chatViewModel: chatViewModel, authViewModel: authViewModel))
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                WhiteGlassBackground()
                    .ignoresSafeArea()
                ScrollView {
                    LazyVStack(spacing: 16) {
                        SettingsSectionCard {
                            VStack(spacing: 0) {
                                NavigationLink(value: SettingsRoute.account) {
                                    SettingsMenuRow(
                                        title: "账号与安全",
                                        subtitle: homeSnapshot.accountSubtitle,
                                        icon: "person.crop.circle"
                                    )
                                }
                                SettingsDivider()
                                NavigationLink(value: SettingsRoute.legal) {
                                    SettingsMenuRow(title: "协议与隐私", subtitle: "用户协议、隐私政策", icon: "doc.text")
                                }
                            }
                        }

                        SettingsSectionCard {
                            VStack(spacing: 0) {
                                NavigationLink(value: SettingsRoute.connection) {
                                    SettingsMenuRow(title: "远程设备", subtitle: homeSnapshot.connectionStatus, icon: "desktopcomputer")
                                }
                                SettingsDivider()
                                NavigationLink(value: SettingsRoute.cli) {
                                    SettingsMenuRow(title: "CLI", subtitle: homeSnapshot.selectedCLI == "claude" ? "Claude Code" : "Codex", icon: "terminal")
                                }
                            }
                        }

                        SettingsSectionCard {
                            VStack(spacing: 0) {
                                NavigationLink(value: SettingsRoute.appUpdate) {
                                    SettingsMenuRow(title: "在线更新", subtitle: appVersionText, icon: "arrow.down.circle")
                                }
                                SettingsDivider()
                                SettingsMenuRow(title: "关于 Codevoke", subtitle: appVersionText, icon: "info.circle", showsChevron: false)
                            }
                        }

                        AppFooterView(footer: authViewModel.appFooter)
                            .padding(.top, 4)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle(L10n.key("设置"))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear(perform: refreshHomeSnapshot)
            .task {
                await authViewModel.loadAppFooterIfNeeded()
            }
            .navigationDestination(for: SettingsRoute.self) { route in
                destination(for: route)
            }
            .toolbar {
                ToolbarItem(placement: .codevokeTopBarLeading) {
                    Button {
                        close()
                    } label: {
                        SettingsCloseButtonLabel()
                    }
                    .buttonStyle(.codevokePress)
                    .accessibilityLabel(L10n.string("关闭设置"))
                }
            }
        }
        .sheet(item: legalDocumentBinding) { document in
            LegalDocumentSheet(document: document)
                .codevokePresentationCornerRadius(28)
        }
    }

    private func refreshHomeSnapshot() {
        let snapshot = SettingsHomeSnapshot(chatViewModel: chatViewModel, authViewModel: authViewModel)
        if homeSnapshot != snapshot {
            homeSnapshot = snapshot
        }
    }

    @ViewBuilder
    private func destination(for route: SettingsRoute) -> some View {
        switch route {
        case .account:
            SettingsAccountPage(authViewModel: authViewModel)
        case .legal:
            SettingsLegalPage(authViewModel: authViewModel)
        case .connection:
            SettingsConnectionPage(viewModel: chatViewModel, authViewModel: authViewModel, close: close)
        case .cli:
            SettingsCLIPage(viewModel: chatViewModel)
        case .changePassword:
            SettingsChangePasswordPage(authViewModel: authViewModel)
        case .accountDeletion:
            AccountDeletionPage(authViewModel: authViewModel) {
                if !navigationPath.isEmpty {
                    navigationPath.removeLast()
                }
            }
        case .appUpdate:
            SettingsAppUpdatePage()
        }
    }

    private var legalDocumentBinding: Binding<RemoteLegalDocument?> {
        Binding(
            get: { authViewModel.selectedLegalDocument },
            set: { value in
                if value == nil {
                    authViewModel.dismissLegalDocument()
                }
            }
        )
    }

    private var appVersionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return L10n.format("版本 %@ (%@)", version, build)
    }
}

private struct SettingsAppUpdatePage: View {
    @State private var message = ""
    @State private var updateURL: URL?
    @State private var isChecking = false
    private let client = RemoteLegalClient()

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        SettingsPageContainer(title: "在线更新") {
            SettingsSectionCard {
                VStack(alignment: .leading, spacing: 14) {
                    SettingsCardTitle("当前版本", subtitle: L10n.format("版本 %@ (%@)", version, buildNumber))
                    if !message.isEmpty {
                        Text(message)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.codevokeMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 10) {
                        Button {
                            Task { await checkForUpdate() }
                        } label: {
                            Text(L10n.key(isChecking ? "检查中..." : "检查更新"))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.codevokeInk, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.codevokePress)
                        .disabled(isChecking)
                        if let updateURL {
                            Button {
                                UIApplication.shared.open(updateURL)
                            } label: {
                                Text(L10n.key("前往商店"))
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Color.codevokeInk)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.codevokeHairline, lineWidth: 1))
                            }
                            .buttonStyle(.codevokePress)
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    @MainActor
    private func checkForUpdate() async {
        isChecking = true
        updateURL = nil
        message = L10n.string("正在检查更新...")
        do {
            let result = try await client.checkAppUpdate(version: version, buildNumber: buildNumber)
            if result.updateAvailable {
                updateURL = URL(string: result.appStoreUrl.isEmpty ? result.downloadUrl : result.appStoreUrl)
                let buildText = result.latestBuildNumber.isEmpty ? "" : " (\(result.latestBuildNumber))"
                let forceText = result.forceUpdate ? L10n.string("，这是强制更新") : ""
                message = L10n.format("发现新版 %@%@%@。%@", result.latestVersion, buildText, forceText, result.releaseNotes)
            } else {
                message = L10n.string("当前已是最新版本。")
            }
        } catch {
            message = error.localizedDescription
        }
        isChecking = false
    }
}

private struct SettingsCloseButtonLabel: View {
    var body: some View {
        if #available(iOS 26.0, *) {
            Image(systemName: "chevron.backward")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.codevokeInk)
                .frame(width: 36, height: 44)
                .contentShape(Rectangle())
        } else {
            Image(systemName: "chevron.backward")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.codevokeInk)
                .frame(width: 44, height: 44)
                .codevokeCircleGlass()
                .overlay(Circle().stroke(Color.codevokeGlassStroke, lineWidth: 1))
                .shadow(color: .black.opacity(0.06), radius: 14, x: 0, y: 7)
        }
    }
}

private struct SettingsAccountPage: View {
    @ObservedObject var authViewModel: AuthViewModel

    var body: some View {
        SettingsPageContainer(title: "账号与安全") {
            SettingsSectionCard {
                VStack(alignment: .leading, spacing: 14) {
                    SettingsCardTitle("当前账号", subtitle: "Codevoke 远程账号")
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(Color.codevokeInk)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(authViewModel.currentSession?.user.displayAccount ?? L10n.string("已登录"))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.codevokeInk)
                            Text(L10n.key("状态正常"))
                                .font(.system(size: 12))
                                .foregroundStyle(Color.codevokeMuted)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .padding(16)
            }

            SettingsSectionCard {
                VStack(spacing: 0) {
                    NavigationLink(value: SettingsRoute.changePassword) {
                        SettingsMenuRow(title: "修改密码", subtitle: "使用当前密码验证", icon: "lock.rotation")
                    }
                    SettingsDivider()
                    Button {
                        Task { await authViewModel.clearSession() }
                    } label: {
                        SettingsActionRow(title: "退出登录", subtitle: "清除本机登录状态", icon: "rectangle.portrait.and.arrow.right", tint: .red.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                    SettingsDivider()
                    NavigationLink(value: SettingsRoute.accountDeletion) {
                        SettingsActionRow(title: "注销账号", subtitle: "删除账号与远程服务数据", icon: "trash", tint: .red)
                    }
                    .buttonStyle(.plain)
                }
            }

            SettingsMessageView(message: authViewModel.accountDeletionMessage)
        }
    }
}

private struct AccountDeletionPage: View {
    @ObservedObject var authViewModel: AuthViewModel
    let close: () -> Void
    @State private var confirmAccount = ""
    @State private var confirmDestroy = ""
    @State private var confirmWaiveRights = ""
    @State private var reason = ""

    private let requiredAccount = "我确认注销账号"
    private let requiredDestroy = "确认销毁"
    private let requiredCleanup = "确认清理远程连接数据"

    var body: some View {
        ZStack {
            WhiteGlassBackground()
                .ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SettingsSectionCard {
                        VStack(alignment: .leading, spacing: 12) {
                            SettingsCardTitle("注销账号", subtitle: "注销成功后账号不可恢复")
                            deletionBullet("远程账号、登录令牌、设备、连接授权、协议确认和服务状态主数据会被删除。")
                            deletionBullet("后台仅保留脱敏注销记录，以及注销前设备与连接状态快照用于审计与争议处理。")
                        }
                        .padding(16)
                    }

                    SettingsSectionCard {
                        VStack(alignment: .leading, spacing: 12) {
                            SettingsTextField(L10n.format("输入：%@", localizedRequiredAccount), text: $confirmAccount, placeholder: requiredAccount)
                            SettingsTextField(L10n.format("输入：%@", localizedRequiredDestroy), text: $confirmDestroy, placeholder: requiredDestroy)
                            SettingsTextField(L10n.format("输入：%@", localizedRequiredCleanup), text: $confirmWaiveRights, placeholder: requiredCleanup)
                            SettingsTextField("注销原因", text: $reason, placeholder: "选填")
                            SettingsMessageView(message: authViewModel.accountDeletionMessage)
                            Button {
                                Task {
                                    let ok = await authViewModel.requestAccountDeletion(
                                        confirmAccount: requiredAccount,
                                        confirmDestroy: requiredDestroy,
                                        confirmWaiveRights: requiredCleanup,
                                        reason: reason
                                    )
                                    if ok { close() }
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    if authViewModel.accountDeletionSubmitting {
                                        ProgressView()
                                            .controlSize(.mini)
                                    } else {
                                        Image(systemName: "trash")
                                    }
                                    Text(L10n.key(authViewModel.accountDeletionSubmitting ? "注销中" : "确认注销账号"))
                                }
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(Color.red, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                            }
                            .buttonStyle(.codevokePress)
                            .disabled(!canSubmit || authViewModel.accountDeletionSubmitting)
                        }
                        .padding(16)
                    }
                }
                .padding(16)
                .padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle(L10n.key("注销账号"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .codevokeTopBarLeading) {
                Button(L10n.string("取消")) { close() }
                    .foregroundStyle(Color.codevokeInk)
            }
        }
    }

    private var canSubmit: Bool {
        confirmationMatches(confirmAccount, canonical: requiredAccount) &&
            confirmationMatches(confirmDestroy, canonical: requiredDestroy) &&
            confirmationMatches(confirmWaiveRights, canonical: requiredCleanup)
    }

    private var localizedRequiredAccount: String { L10n.string(requiredAccount) }
    private var localizedRequiredDestroy: String { L10n.string(requiredDestroy) }
    private var localizedRequiredCleanup: String { L10n.string(requiredCleanup) }

    private func confirmationMatches(_ value: String, canonical: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == canonical || trimmed == L10n.string(canonical)
    }

    private func deletionBullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.red.opacity(0.78))
                .padding(.top, 2)
            Text(L10n.key(text))
                .font(.system(size: 12))
                .foregroundStyle(Color.codevokeMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SettingsChangePasswordPage: View {
    @ObservedObject var authViewModel: AuthViewModel

    var body: some View {
        SettingsPageContainer(title: "修改密码") {
            SettingsSectionCard {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsCardTitle("账号安全", subtitle: "修改成功后需要重新登录")
                    SettingsSecureField("当前密码", text: $authViewModel.changePasswordCurrent, placeholder: "请输入当前密码")
                    SettingsSecureField("新密码", text: $authViewModel.changePasswordNew, placeholder: "请输入新密码")
                    SettingsSecureField("确认新密码", text: $authViewModel.changePasswordConfirm, placeholder: "再次输入新密码")
                    SettingsMessageView(message: authViewModel.changePasswordMessage)
                    Button {
                        Task { await authViewModel.requestChangePassword() }
                    } label: {
                        Text(L10n.key(authViewModel.changePasswordSubmitting ? "修改中" : "确认修改"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Color.black, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                    }
                    .buttonStyle(.codevokePress)
                    .disabled(!authViewModel.canSubmitChangePassword)
                }
                .padding(16)
            }
        }
    }
}

private struct SettingsConnectionPage: View {
    @ObservedObject var viewModel: ChatViewModel
    @ObservedObject var authViewModel: AuthViewModel
    @StateObject private var connectViewModel = DeviceConnectViewModel()
    @State private var mode: RemoteConnectionMode = .devices
    let close: () -> Void

    var body: some View {
        SettingsPageContainer(title: "远程设备") {
            connectionHeader
            RemoteConnectionModePicker(selection: $mode)
            if mode == .devices {
                devicesCard
                codeEntryShortcut
            } else {
                deviceCodeCard
                resolvedDeviceCard
            }
            connectionStatusCard
        }
        .task {
            if authViewModel.remoteDevices.isEmpty {
                await authViewModel.loadRemoteDevices()
            }
        }
    }

    private var connectionHeader: some View {
        VStack(alignment: .leading, spacing: 7) {
                Text(L10n.key(mode == .devices ? "选择电脑" : "输入设备码"))
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color.codevokeInk)
            Text(L10n.key(mode == .devices ? "连接已登录账号的远程设备，或输入设备码。" : "设备码在电脑端远程账号卡片中查看。"))
                .font(.system(size: 13))
                .foregroundStyle(Color.codevokeMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }

    private var devicesCard: some View {
        SettingsSectionCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    SettingsCardTitle("我的设备", subtitle: "来自当前账号的电脑")
                    Spacer(minLength: 0)
                    Button(L10n.string(authViewModel.remoteDevicesLoading ? "刷新中…" : "刷新")) {
                        Task { await authViewModel.loadRemoteDevices() }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.codevokeInk)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.72), in: Capsule())
                    .overlay(Capsule().stroke(Color.black.opacity(0.06), lineWidth: 1))
                    .buttonStyle(.codevokePress)
                    .disabled(authViewModel.remoteDevicesLoading)
                }

                if authViewModel.remoteDevicesLoading && authViewModel.remoteDevices.isEmpty {
                    SettingsEmptyRow(icon: "desktopcomputer", text: "正在加载远程设备…")
                } else if authViewModel.remoteDevices.isEmpty {
                    SettingsEmptyRow(icon: "desktopcomputer", text: "还没有远程设备。请先在电脑端登录并启用远程连接。")
                } else {
                    VStack(spacing: 10) {
                        ForEach(authViewModel.remoteDevices) { device in
                            remoteDeviceRow(device)
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private var codeEntryShortcut: some View {
        Button {
            mode = .code
        } label: {
            SettingsSectionCard {
                HStack(spacing: 12) {
                    Image(systemName: "number.square")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.codevokeInk)
                        .frame(width: 42, height: 42)
                        .background(Color.codevokeSoft, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.key("输入设备码"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.codevokeInk)
                        Text(L10n.key("用电脑端显示的固定设备码连接"))
                            .font(.system(size: 12))
                            .foregroundStyle(Color.codevokeMuted)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.codevokeMuted.opacity(0.6))
                }
                .padding(16)
            }
        }
        .buttonStyle(.plain)
    }

    private var deviceCodeCard: some View {
        SettingsSectionCard {
            VStack(alignment: .leading, spacing: 14) {
                SettingsCardTitle("固定设备码", subtitle: "支持已登录账号的桌面设备")
                SettingsTextField("设备码", text: $connectViewModel.deviceCode, placeholder: "ABCD-EFGH-12")
                HStack(spacing: 10) {
                    Button(L10n.string(connectViewModel.isResolvingCode ? "查找中…" : "查找设备")) {
                        Task { await connectViewModel.resolveDeviceCode(session: authViewModel.currentSession) }
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.codevokeInk)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.black.opacity(0.06), lineWidth: 1))
                    .buttonStyle(.codevokePress)
                    .disabled(connectViewModel.isResolvingCode)

                    Button(L10n.string(connectViewModel.isConnecting ? "连接中…" : "连接")) {
                        if let resolved = connectViewModel.resolvedDevice {
                            Task { await connect(deviceId: resolved.deviceId) }
                        }
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color.black, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .buttonStyle(.codevokePress)
                    .disabled(connectViewModel.resolvedDevice == nil || connectViewModel.isConnecting)
                }
                Text(L10n.key("解析成功后显示设备名称和确认状态。"))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.codevokeMuted)
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private var resolvedDeviceCard: some View {
        if let resolved = connectViewModel.resolvedDevice {
            SettingsSectionCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        RemoteDeviceIcon(platform: resolved.platform)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(resolved.deviceName)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.codevokeInk)
                            Text("\(platformName(resolved.platform)) · \(L10n.string(resolved.requiresConfirm ? "需要电脑端确认" : "可直接连接"))")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.codevokeMuted)
                        }
                        Spacer(minLength: 0)
                    }
                    Divider().opacity(0.32)
                    Text(L10n.key("等待确认时保留在本页，不跳转、不遮挡主聊天页。"))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.codevokeMuted)
                    Button {
                        Task { await connect(deviceId: resolved.deviceId) }
                    } label: {
                        Text(L10n.key(connectViewModel.isConnecting ? "连接中…" : "连接这台电脑"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.black, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .buttonStyle(.codevokePress)
                    .disabled(connectViewModel.isConnecting)
                }
                .padding(16)
            }
        }
    }

    private func remoteDeviceRow(_ device: RemoteDevice) -> some View {
        HStack(spacing: 12) {
            RemoteDeviceIcon(platform: device.platform, enabled: device.remoteEnabled && device.status == "active")
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(device.online ? Color.green : Color.codevokeMuted.opacity(0.38))
                        .frame(width: 7, height: 7)
                    Text(device.deviceName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.codevokeInk)
                        .lineLimit(2)
                }
                Text(deviceSubtitle(device))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.codevokeMuted)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Button(L10n.string(connectViewModel.isConnecting ? "连接中…" : "连接")) {
                Task { await connect(deviceId: device.id) }
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.black, in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .buttonStyle(.codevokePress)
            .disabled(connectViewModel.isConnecting || !device.remoteEnabled || device.status != "active")
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.white.opacity(device.remoteEnabled ? 0.62 : 0.36), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.black.opacity(0.045), lineWidth: 1))
    }

    @ViewBuilder
    private var connectionStatusCard: some View {
        let diagnostics = RemoteUserFacingText.diagnostics(
            connectionId: connectViewModel.latestConnectionId,
            transport: connectViewModel.latestTransport,
            reason: connectViewModel.latestReason
        )
        if connectViewModel.message != nil || diagnostics != nil {
            SettingsSectionCard {
                VStack(alignment: .leading, spacing: 6) {
                    if let message = connectViewModel.message {
                        Text(message)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(message.contains("失败") || message.contains("超时") ? .red.opacity(0.85) : Color.codevokeMuted)
                    }
                    if let diagnostics {
                        Text(diagnostics)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.codevokeMuted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }
        }
    }

    private func connect(deviceId: Int) async {
        guard let config = await connectViewModel.connect(deviceId: deviceId, session: authViewModel.currentSession) else { return }
        viewModel.config = config
        viewModel.saveConnectionConfig()
        close()
    }

    private func deviceSubtitle(_ device: RemoteDevice) -> String {
        platformName(device.platform)
    }

    private func platformName(_ raw: String?) -> String {
        switch raw?.lowercased() {
        case "macos": "macOS"
        case "windows": "Windows"
        case "linux": "Linux"
        case let value? where !value.isEmpty: value
        default: L10n.string("电脑")
        }
    }
}

private enum RemoteConnectionMode: String, CaseIterable {
    case devices
    case code

    var title: String {
        switch self {
        case .devices: L10n.string("我的设备")
        case .code: L10n.string("设备码")
        }
    }
}

private struct RemoteConnectionModePicker: View {
    @Binding var selection: RemoteConnectionMode

    var body: some View {
        HStack(spacing: 0) {
            ForEach(RemoteConnectionMode.allCases, id: \.self) { mode in
                Button {
                    selection = mode
                } label: {
                    Text(mode.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selection == mode ? .white : Color.codevokeMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(selection == mode ? Color.black : .clear, in: Capsule())
                }
                .buttonStyle(.codevokePress)
            }
        }
        .padding(5)
        .background(.white.opacity(0.68), in: Capsule())
        .overlay(Capsule().stroke(Color.black.opacity(0.06), lineWidth: 1))
    }
}

private struct RemoteDeviceIcon: View {
    let platform: String?
    var enabled = true

    var body: some View {
        Image(systemName: iconName)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(enabled ? Color.codevokeInk : Color.codevokeMuted.opacity(0.48))
            .frame(width: 38, height: 38)
            .background(Color.codevokeSoft.opacity(enabled ? 1 : 0.7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var iconName: String {
        switch platform?.lowercased() {
        case "windows": "pc"
        case "linux": "terminal"
        default: "desktopcomputer"
        }
    }
}

private struct SettingsCLIPage: View {
    @ObservedObject var viewModel: ChatViewModel

    private let cliOptions: [(id: String, title: String, subtitle: String)] = [
        ("claude", "Claude Code", "Anthropic Claude CLI"),
        ("codex", "Codex", "OpenAI Codex CLI")
    ]

    var body: some View {
        SettingsPageContainer(title: "CLI") {
            // Audit C-05: surface ack errors from CLI / model / permission /
            // reasoning switches so the user sees feedback in the page they
            // actually clicked in (instead of silently logging to lastError).
            if let err = viewModel.lastError, !err.isEmpty {
                SettingsSectionCard {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(err)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.red.opacity(0.9))
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Button(L10n.string("收起")) { viewModel.lastError = nil }
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.codevokeInk)
                    }
                    .padding(12)
                }
            }
            SettingsSectionCard {
                VStack(alignment: .leading, spacing: 10) {
                    SettingsCardTitle("命令行后端", subtitle: "选择消息使用的 CLI")
                    ForEach(cliOptions, id: \.id) { option in
                        // Audit C-03: surface capability.errorMessage and
                        // disable the row when the CLI is unavailable.
                        let cap = viewModel.capability(forCLI: option.id)
                        let unavailable = cap?.executableAvailable == false
                        let errorMessage = cap?.errorMessage
                        SettingsOptionRow(
                            title: option.title,
                            subtitle: unavailable
                                ? (errorMessage ?? L10n.format("%@ 不可用", option.title)) : option.subtitle,
                            icon: option.id == "claude" ? "sparkles" : "circle.hexagongrid.fill",
                            selected: viewModel.selectedCLI == option.id
                        ) {
                            guard !unavailable else { return }
                            viewModel.selectCLI(option.id)
                        }
                        .opacity(unavailable ? 0.5 : 1)
                    }
                }
                .padding(16)
            }
        }
    }
}

private struct SettingsLegalPage: View {
    @ObservedObject var authViewModel: AuthViewModel

    var body: some View {
        SettingsPageContainer(title: "协议与隐私") {
            SettingsSectionCard {
                VStack(spacing: 0) {
                    ForEach(RemoteLegalDocumentType.allCases, id: \.self) { type in
                        Button {
                            authViewModel.presentLegalDocument(type)
                        } label: {
                            SettingsActionRow(title: type.title, subtitle: authViewModel.legalDocuments[type]?.version ?? L10n.string("点击查看"), icon: "doc.text")
                        }
                        .buttonStyle(.plain)
                        if type != RemoteLegalDocumentType.allCases.last {
                            SettingsDivider()
                        }
                    }
                }
            }
            SettingsMessageView(message: authViewModel.documentMessage)
        }
        .task {
            await authViewModel.loadLegalDocumentsIfNeeded()
        }
    }
}

private struct SettingsPageContainer<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            WhiteGlassBackground()
                .ignoresSafeArea()
            ScrollView {
                LazyVStack(spacing: 16) {
                    content
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle(L10n.key(title))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SettingsSectionCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .codevokeGlass(cornerRadius: 26)
            .background(.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.codevokeHairline, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.055), radius: 16, x: 0, y: 8)
    }
}

private struct SettingsPlainIcon: View {
    let systemName: String
    var tint: Color = Color.codevokeInk.opacity(0.58)
    var size: CGFloat = 16
    var weight: Font.Weight = .semibold
    var frame: CGFloat = 31

    var body: some View {
        Image(systemName: systemName)
            .symbolRenderingMode(.monochrome)
            .font(.system(size: size, weight: weight))
            .foregroundStyle(tint)
            .frame(width: frame, height: frame)
    }
}

private struct SettingsMenuRow: View {
    let title: String
    let subtitle: String
    let icon: String
    var showsChevron = true

    var body: some View {
        HStack(spacing: 12) {
            SettingsPlainIcon(systemName: icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.key(title))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.codevokeInk)
                Text(L10n.key(subtitle))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.codevokeMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.codevokeMuted.opacity(0.55))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}

private struct SettingsActionRow: View {
    let title: String
    let subtitle: String
    let icon: String
    var tint: Color = Color.codevokeInk

    var body: some View {
        HStack(spacing: 12) {
            SettingsPlainIcon(
                systemName: icon,
                tint: tint.opacity(0.72)
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.key(title))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                Text(L10n.key(subtitle))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.codevokeMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}

struct SettingsCardTitle: View {
    let title: String
    let subtitle: String

    init(_ title: String, subtitle: String) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.key(title))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.codevokeInk)
            Text(L10n.key(subtitle))
                .font(.system(size: 11))
                .foregroundStyle(Color.codevokeMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsTextField: View {
    let title: String
    @Binding var text: String
    let placeholder: String

    init(_ title: String, text: Binding<String>, placeholder: String) {
        self.title = title
        self._text = text
        self.placeholder = placeholder
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.key(title))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.codevokeMuted)
            TextField(L10n.string(placeholder), text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 15))
                .padding(11)
                .codevokeGlass(cornerRadius: 16)
                .background(.white.opacity(0.56), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.codevokeGlassStroke, lineWidth: 1))
        }
    }
}

private struct SettingsSecureField: View {
    let title: String
    @Binding var text: String
    let placeholder: String

    init(_ title: String, text: Binding<String>, placeholder: String) {
        self.title = title
        self._text = text
        self.placeholder = placeholder
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.key(title))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.codevokeMuted)
            SecureField(L10n.string(placeholder), text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 15))
                .padding(11)
                .codevokeGlass(cornerRadius: 16)
                .background(.white.opacity(0.56), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.codevokeGlassStroke, lineWidth: 1))
        }
    }
}

private struct SettingsOptionRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                SettingsPlainIcon(
                    systemName: icon,
                    tint: Color.codevokeInk.opacity(selected ? 0.78 : 0.5),
                    size: 13,
                    frame: 24
                )
                VStack(alignment: .leading, spacing: 1) {
                    Text(L10n.key(title))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.codevokeInk)
                        .lineLimit(1)
                    Text(L10n.key(subtitle))
                        .font(.system(size: 10))
                        .foregroundStyle(Color.codevokeMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.codevokeInk)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(selected ? Color.white.opacity(0.85) : Color.white.opacity(0.45), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(selected ? Color.black.opacity(0.18) : .white.opacity(0.6), lineWidth: 1))
        }
        .buttonStyle(.codevokePress)
    }
}

private struct SettingsEmptyRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(Color.codevokeMuted)
            Text(L10n.key(text))
                .font(.system(size: 12))
                .foregroundStyle(Color.codevokeMuted)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }
}

private struct SettingsStatusDot: View {
    let status: String

    var body: some View {
        let color: Color = switch status {
        case "已连接": .green
        case "正在连接": .orange
        default: .red.opacity(0.7)
        }
        Circle().fill(color).frame(width: 8, height: 8)
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 57)
            .opacity(0.32)
    }
}

private struct SettingsMessageView: View {
    let message: String?

    var body: some View {
        if let message, !message.isEmpty {
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(message.contains("成功") || message.contains("已") ? Color.codevokeMuted : .red.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 2)
        }
    }
}
