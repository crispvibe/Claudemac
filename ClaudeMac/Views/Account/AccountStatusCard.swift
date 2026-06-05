import AppKit
import SwiftUI

struct AccountRemoteControlPanel: View {
    var body: some View {
        AccountStatusCard()
            .padding(24)
            .background {
                ZStack {
                    VisualEffectView(material: .popover, blendingMode: .withinWindow)
                        .opacity(0.94)
                    AppTheme.cardSurface.opacity(0.94)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(AppTheme.hairline, lineWidth: 1))
            .shadow(color: Color.black.opacity(0.08), radius: 22, y: 12)
    }
}

struct AccountStatusCard: View {
    @EnvironmentObject private var accountAuth: AccountAuthViewModel
    @EnvironmentObject private var deviceProvisioning: DeviceProvisioningViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "person.crop.circle.fill.badge.checkmark")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text(accountAuth.currentSession.map { "已登录 \(accountRemoteDisplayAccount($0.user))" } ?? "未登录")
                        .font(.system(size: 14, weight: .semibold))
                    Text(statusText)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("登出") {
                    Task { await accountAuth.logout() }
                }
                .buttonStyle(AccountSecondaryButtonStyle())
            }

            if accountAuth.currentSession != nil {
                deviceSettings
                deviceCodeRow
                if let signalingStatus = deviceProvisioning.signalingStatus {
                    Text(signalingStatus)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                if deviceProvisioning.pendingApproval != nil {
                    approvalCard
                }
                if let message = deviceProvisioning.message {
                    AccountMessageView(message: message, severity: deviceProvisioning.messageSeverity)
                }
            }
        }
    }

    private var statusText: String {
        if deviceProvisioning.isBootstrapping { return "正在注册本机设备…" }
        if let device = deviceProvisioning.device {
            return "设备：\(device.deviceName) · \(device.status)"
        }
        return "登录后会自动注册这台 Mac。"
    }

    private var deviceSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                AccountTextField(title: "设备名", systemImage: "desktopcomputer", text: $deviceProvisioning.deviceNameDraft)
                Picker("", selection: $deviceProvisioning.approvalPolicy) {
                    ForEach(RemoteDeviceApprovalPolicy.allCases) { policy in
                        Text(policy.title).tag(policy)
                    }
                }
                .labelsHidden()
                .frame(width: 150)
                Button(deviceProvisioning.isSavingDevice ? "保存中…" : "保存") {
                    if let session = accountAuth.currentSession {
                        Task { await deviceProvisioning.saveDeviceSettings(session: session) }
                    }
                }
                .buttonStyle(AccountSecondaryButtonStyle())
                .disabled(deviceProvisioning.isSavingDevice)
            }
        }
    }

    private var approvalCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("新的 iOS 连接请求")
                .font(.system(size: 12, weight: .semibold))
            if let pending = deviceProvisioning.pendingApproval {
                Text("请求编号：\(pending.connectionId ?? pending.id) · 来源设备：\(pending.fromDeviceId.map(String.init) ?? "未知")")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Button("允许一次") {
                    Task { await deviceProvisioning.approvePendingConnection(remember: false) }
                }
                .buttonStyle(AccountSecondaryButtonStyle())

                Button("拒绝") {
                    Task { await deviceProvisioning.rejectPendingConnection() }
                }
                .buttonStyle(AccountSecondaryButtonStyle())

                Button("总是允许") {
                    Task { await deviceProvisioning.approvePendingConnection(remember: true) }
                }
                .buttonStyle(AccountSecondaryButtonStyle())
            }
        }
        .padding(12)
        .background(AppTheme.inputSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AppTheme.hairline, lineWidth: 1))
    }

    private var deviceCodeRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("设备码")
                .font(.system(size: 12, weight: .semibold))
            HStack(spacing: 10) {
                Text(deviceProvisioning.displayedDeviceCode ?? deviceCodeFallback)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.inputSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AppTheme.hairline, lineWidth: 1))

                Button("复制") { copyDeviceCode() }
                    .buttonStyle(AccountSecondaryButtonStyle())
                    .disabled(deviceProvisioning.deviceCode?.isEmpty != false)

                Button(deviceProvisioning.isResettingDeviceCode ? "重置中…" : "重置") {
                    if let session = accountAuth.currentSession {
                        Task { await deviceProvisioning.resetDeviceCode(session: session) }
                    }
                }
                .buttonStyle(AccountSecondaryButtonStyle())
                .disabled(deviceProvisioning.isResettingDeviceCode)
            }
            Text("其他账号使用设备码连接；同一账号设备可直接在设备列表里连接。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var deviceCodeFallback: String {
        if let hint = deviceProvisioning.deviceCodeHint, !hint.isEmpty {
            return "仅有尾号 ****-\(hint)，请重置后显示完整设备码"
        }
        return deviceProvisioning.isBootstrapping ? "正在读取…" : "未生成"
    }

    private func copyDeviceCode() {
        guard let code = deviceProvisioning.deviceCode, !code.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(accountRemoteFormattedDeviceCode(code), forType: .string)
    }
}
