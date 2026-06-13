import SwiftUI

struct DeviceListView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @StateObject private var listViewModel = DeviceListViewModel()
    @StateObject private var connectViewModel = DeviceConnectViewModel()
    @State private var chatConfig: RemoteChatConfig?

    var body: some View {
        Group {
            if chatConfig != nil {
                RootView(authViewModel: authViewModel, initialConfig: chatConfig)
            } else {
                NavigationStack {
                    ZStack {
                        WhiteGlassBackground()
                            .ignoresSafeArea()
                        ScrollView {
                            VStack(alignment: .leading, spacing: 18) {
                                header
                                deviceSection
                                codeEntryLink
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 22)
                        }
                    }
                    .navigationTitle(L10n.key("远程设备"))
                    .toolbar {
                        ToolbarItem(placement: .acodeTopBarTrailing) {
                            Button {
                                Task { await listViewModel.load(session: authViewModel.currentSession) }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(Color.acodeInk)
                                    .frame(width: 44, height: 44)
                                    .acodeCircleGlass()
                                    .overlay(Circle().stroke(Color.acodeGlassStroke, lineWidth: 1))
                                    .shadow(color: .black.opacity(0.06), radius: 14, x: 0, y: 7)
                            }
                            .buttonStyle(.acodePress)
                            .disabled(listViewModel.isLoading)
                        }
                    }
                    .onAppear {
                        listViewModel.startPresenceUpdates(session: authViewModel.currentSession)
                    }
                    .onDisappear {
                        listViewModel.stopPresenceUpdates()
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.key("选择电脑"))
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color.acodeInk)
            Text(L10n.key("优先局域网直连，跨网时走 P2P 或公网端口映射。"))
                .font(.system(size: 14))
                .foregroundStyle(Color.acodeMuted)
        }
    }

    private var deviceSection: some View {
        SettingsSectionCard {
            VStack(alignment: .leading, spacing: 12) {
                SettingsCardTitle("我的设备", subtitle: "来自当前账号的桌面设备")
                if listViewModel.isLoading {
                    ProgressView()
                        .tint(.black)
                } else if listViewModel.devices.isEmpty {
                    Text(L10n.key("还没有远程设备。请先在电脑端登录并注册设备。"))
                        .font(.system(size: 13))
                        .foregroundStyle(Color.acodeMuted)
                } else {
                    ForEach(listViewModel.devices) { device in
                        deviceRow(device)
                    }
                }
                if let message = listViewModel.message ?? connectViewModel.message {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.acodeMuted)
                }
                if let diagnostics = RemoteUserFacingText.diagnostics(
                    connectionId: connectViewModel.latestConnectionId,
                    transport: connectViewModel.latestTransport,
                    reason: connectViewModel.latestReason
                ) {
                    Text(diagnostics)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.acodeMuted)
                }
            }
            .padding(16)
        }
    }

    private var codeEntryLink: some View {
        NavigationLink {
            DeviceCodeEntryView(authViewModel: authViewModel, connectViewModel: connectViewModel) { config in
                chatConfig = config
            }
        } label: {
            SettingsSectionCard {
                HStack(spacing: 12) {
                    Image(systemName: "number.square")
                        .font(.system(size: 22, weight: .semibold))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.key("输入设备码"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.acodeInk)
                        Text(L10n.key("用电脑端显示的固定设备码发起连接。"))
                            .font(.system(size: 12))
                            .foregroundStyle(Color.acodeMuted)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(Color.acodeMuted)
                }
                .padding(16)
            }
        }
        .buttonStyle(.plain)
    }

    private func deviceRow(_ device: RemoteDevice) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.acodeInk)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(device.online ? Color.green : Color.acodeMuted.opacity(0.38))
                        .frame(width: 7, height: 7)
                    Text(device.deviceName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.acodeInk)
                        .lineLimit(2)
                }
                Text(deviceSubtitle(device))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.acodeMuted)
                    .lineLimit(2)
            }
            Spacer()
            Button(L10n.string(connectViewModel.isConnecting ? "连接中…" : "连接")) {
                Task {
                    if let config = await connectViewModel.connect(deviceId: device.id, session: authViewModel.currentSession, device: device) {
                        chatConfig = config
                    }
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.black, in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .buttonStyle(.acodePress)
            .disabled(connectViewModel.isConnecting || !device.remoteEnabled || device.status != "active")
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, 8)
    }

    private func deviceSubtitle(_ device: RemoteDevice) -> String {
        let platform = device.platform ?? "macos"
        if device.lanEndpoint != nil, !(device.transientToken?.isEmpty ?? true) {
            return L10n.format("%@ · 局域网可连接", platform)
        }
        if device.remoteEnabled, device.status == "active" {
            return L10n.format("%@ · 信令可请求", platform)
        }
        if let lastSeenAt = device.lastSeenAt {
            return L10n.format("%@ · 上次活动 %@", platform, lastSeenAt)
        }
        return platform
    }
}
