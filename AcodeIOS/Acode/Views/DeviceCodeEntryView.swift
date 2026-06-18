import SwiftUI

struct DeviceCodeEntryView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @ObservedObject var connectViewModel: DeviceConnectViewModel
    var onConnected: (RemoteChatConfig) -> Void

    var body: some View {
        ZStack {
            WhiteGlassBackground()
                .ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.key("输入设备码"))
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(Color.codevokeInk)
                        Text(L10n.key("设备码可在电脑端远程账号卡片中查看或重置。"))
                            .font(.system(size: 14))
                            .foregroundStyle(Color.codevokeMuted)
                    }

                    SettingsSectionCard {
                        VStack(alignment: .leading, spacing: 12) {
                            SettingsTextField("固定设备码", text: $connectViewModel.deviceCode, placeholder: "ABCD-EFGH-12")
                            Button(L10n.string(connectViewModel.isResolvingCode ? "解析中…" : "查找设备")) {
                                Task { await connectViewModel.resolveDeviceCode(session: authViewModel.currentSession) }
                            }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.codevokeInk)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                            .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.black.opacity(0.06), lineWidth: 1))
                            .buttonStyle(.codevokePress)
                            .disabled(connectViewModel.isResolvingCode)

                            if let resolved = connectViewModel.resolvedDevice {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(resolved.deviceName)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Color.codevokeInk)
                                        .lineLimit(2)
                                    Text("\(resolved.platform) · \(L10n.string(resolved.requiresConfirm ? "需要电脑端确认" : "可直接连接"))")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.codevokeMuted)
                                    Button(L10n.string(connectViewModel.isConnecting ? "连接中…" : "连接这台电脑")) {
                                        Task {
                                            if let config = await connectViewModel.connect(deviceId: resolved.deviceId, session: authViewModel.currentSession) {
                                                onConnected(config)
                                            }
                                        }
                                    }
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(minHeight: 48)
                                    .background(Color.black, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                                    .buttonStyle(.codevokePress)
                                    .disabled(connectViewModel.isConnecting)
                                }
                                .padding(.top, 8)
                            }

                            if let message = connectViewModel.message {
                                Text(message)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.codevokeMuted)
                            }
                            if let diagnostics = RemoteUserFacingText.diagnostics(
                                connectionId: connectViewModel.latestConnectionId,
                                transport: connectViewModel.latestTransport,
                                reason: connectViewModel.latestReason
                            ) {
                                Text(diagnostics)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.codevokeMuted)
                            }
                        }
                        .padding(16)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 22)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle(L10n.key("设备码"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
