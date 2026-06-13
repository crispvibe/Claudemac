import { Copy, Loader2, LogOut, Radio, RefreshCw, ShieldCheck } from "lucide-react";
import { useEffect, useState } from "react";
import type { RemoteConnectResult } from "@shared/account";
import { useAccountRemoteStore } from "../../stores/accountStore";
import {
  connectionStatusLabel,
  deviceCodeFallback,
  formatDeviceCode,
  signalingStatusText
} from "./accountRemoteShared";

const deviceApprovalOptions = [
  { value: "always_ask", label: "每次询问" },
  { value: "allow_anyone", label: "允许任意连接" }
] as const;

type RemoteActionRunner = (label: string, action: () => Promise<unknown>, successMessage?: string) => Promise<boolean>;

export interface AccountStatusCardProps {
  activeConnection?: RemoteConnectResult | null;
  connecting?: boolean;
  embedded?: boolean;
  message?: { kind: "info" | "success" | "error"; text: string } | null;
  onLogout?: () => void;
  onRefreshDevices?: () => void;
  onToggleSignaling?: () => void;
  remoteAction?: string | null;
  runRemoteAction: RemoteActionRunner;
}

export function AccountStatusCard({
  activeConnection = null,
  connecting = false,
  embedded = false,
  message = null,
  onLogout,
  onRefreshDevices,
  onToggleSignaling,
  remoteAction = null,
  runRemoteAction
}: AccountStatusCardProps) {
  const account = useAccountRemoteStore((state) => state.account);
  const device = useAccountRemoteStore((state) => state.device);
  const deviceCode = useAccountRemoteStore((state) => state.deviceCode);
  const devices = useAccountRemoteStore((state) => state.devices);
  const connectionStatus = useAccountRemoteStore((state) => state.connectionStatus);
  const [deviceName, setDeviceName] = useState(device?.deviceName ?? "");
  const [approvalPolicy, setApprovalPolicy] = useState<"always_ask" | "allow_anyone">("always_ask");
  const [remoteEnabled, setRemoteEnabled] = useState(true);
  const isAuthenticated = account.status === "authenticated";
  const isConnected = connectionStatus === "connected";
  const accountLabel = account.displayAccount ?? "未登录";
  const currentRemoteDevice = device?.deviceID ? devices.find((item) => item.id === device.deviceID) : undefined;
  const statusLine = device?.deviceID
    ? `设备：${device.deviceName} · ${currentRemoteDevice?.status ?? "active"}`
    : connecting
      ? "正在注册本机设备…"
      : "登录后会自动注册本机。";

  useEffect(() => {
    setDeviceName(device?.deviceName ?? "");
    const currentRemoteDevice = device?.deviceID ? devices.find((item) => item.id === device.deviceID) : undefined;
    setApprovalPolicy(currentRemoteDevice?.approvalPolicy === "allow_anyone" ? "allow_anyone" : "always_ask");
    setRemoteEnabled(currentRemoteDevice?.remoteEnabled ?? true);
  }, [device?.deviceID, device?.deviceName, devices]);

  function requireBridge() {
    const bridge = window.acode?.accountRemote;
    if (!bridge) {
      throw new Error("Account API is not available.");
    }
    return bridge;
  }

  async function copyDeviceCode() {
    if (!deviceCode.deviceCode) {
      return;
    }
    await navigator.clipboard.writeText(formatDeviceCode(deviceCode.deviceCode));
  }

  return (
    <div className={`account-status-card ${embedded ? "embedded" : ""}`}>
      <header className="account-status-header">
        <div className="account-status-identity">
          <span className="account-status-avatar" aria-hidden="true">
            <ShieldCheck size={20} />
          </span>
          <div>
            <strong>{isAuthenticated ? `已登录 ${accountLabel}` : "未登录"}</strong>
            <span>{statusLine}</span>
          </div>
        </div>
        {isAuthenticated ? (
          <button
            type="button"
            className="account-secondary-button"
            disabled={Boolean(remoteAction)}
            onClick={() => (onLogout ? onLogout() : void runRemoteAction("退出登录", () => requireBridge().logout(), "已退出登录。"))}
          >
            <LogOut size={14} />
            登出
          </button>
        ) : null}
      </header>

      {isAuthenticated ? (
        <>
          <section className="account-status-block">
            <div className="account-status-device-row">
              <label className="account-status-field">
                <span>设备名</span>
                <input
                  className="settings-input compact"
                  value={deviceName}
                  placeholder="本机设备名"
                  onChange={(event) => setDeviceName(event.currentTarget.value)}
                />
              </label>
              <label className="account-status-field compact">
                <span>连接策略</span>
                <select
                  className="settings-select"
                  value={approvalPolicy}
                  onChange={(event) => setApprovalPolicy(event.currentTarget.value as "always_ask" | "allow_anyone")}
                >
                  {deviceApprovalOptions.map((item) => (
                    <option key={item.value} value={item.value}>{item.label}</option>
                  ))}
                </select>
              </label>
              <label className="account-status-checkbox">
                <input checked={remoteEnabled} type="checkbox" onChange={(event) => setRemoteEnabled(event.currentTarget.checked)} />
                <span>允许远程连接</span>
              </label>
              <button
                type="button"
                className="account-secondary-button account-status-save-button settings-inline-button"
                disabled={Boolean(remoteAction) || !device?.deviceID || !deviceName.trim()}
                onClick={() => void runRemoteAction("保存设备", () => requireBridge().updateDevice({
                  approvalPolicy,
                  deviceName: deviceName.trim(),
                  remoteEnabled
                }), "设备设置已保存。")}
              >
                <span>{remoteAction === "保存设备" ? "保存中…" : "保存"}</span>
              </button>
            </div>
          </section>

          <section className="account-status-block">
            <div className="account-status-block-title">设备码</div>
            <div className="account-status-code-row">
              <div className="device-code-box">
                {deviceCode.deviceCode ? formatDeviceCode(deviceCode.deviceCode) : deviceCodeFallback(deviceCode.hint, device?.hasDeviceCode)}
              </div>
              <button type="button" className="account-secondary-button settings-inline-button" disabled={!deviceCode.deviceCode} onClick={() => void copyDeviceCode()}>
                <Copy size={14} />
                <span>复制</span>
              </button>
              <button
                type="button"
                className="account-secondary-button"
                disabled={Boolean(remoteAction) || !device?.deviceID}
                onClick={() => void runRemoteAction("重置设备码", () => requireBridge().resetDeviceCode(), "设备码已重置。")}
              >
                {remoteAction === "重置设备码" ? "重置中…" : "重置"}
              </button>
            </div>
            <p className="account-status-hint">其他账号使用设备码连接；同一账号设备可直接在设备列表里连接。</p>
          </section>

          <section className="account-status-service-row">
            <div className="account-status-service-leading">
              <div className="account-status-service-status">
                <span className="account-status-inline-label">信令</span>
                <span className={`status-badge ${isConnected ? "active" : ""}`}>{connectionStatusLabel(connectionStatus)}</span>
              </div>
              {signalingStatusText(connectionStatus) ? (
                <p className="account-status-hint">{signalingStatusText(connectionStatus)}</p>
              ) : null}
            </div>
            <div className="account-status-service-actions">
              <button
                type="button"
                className="account-secondary-button settings-inline-button"
                disabled={Boolean(remoteAction)}
                onClick={() => (onRefreshDevices ? onRefreshDevices() : void runRemoteAction("刷新设备", () => requireBridge().refreshDevices()))}
              >
                <RefreshCw size={14} />
                <span>刷新设备</span>
              </button>
              <button
                type="button"
                className="settings-primary-button compact settings-inline-button"
                disabled={Boolean(remoteAction)}
                onClick={() => (onToggleSignaling ? onToggleSignaling() : void runRemoteAction(
                  isConnected ? "停止信令" : "启动信令",
                  () => (isConnected ? requireBridge().stopSignaling() : requireBridge().startSignaling())
                ))}
              >
                <Radio size={14} />
                <span>{isConnected ? "停止信令" : "启动信令"}</span>
              </button>
            </div>
          </section>

          {activeConnection ? (
            <div className="remote-connection-banner">
              <span className={`remote-transport-badge ${activeConnection.transport}`}>
                {activeConnection.transport === "lan" ? "局域网" : activeConnection.transport === "tunnel" ? "跨网" : "公网"}
              </span>
              <div>
                <strong>
                  {activeConnection.transport === "lan"
                    ? `${activeConnection.host}:${activeConnection.port}`
                    : `连接 #${activeConnection.connectionId ?? "?"}`}
                </strong>
                {activeConnection.message ? <span>{activeConnection.message}</span> : null}
              </div>
            </div>
          ) : null}

          {remoteAction ? (
            <p className="account-action-status"><Loader2 size={14} /> 正在执行：{remoteAction}</p>
          ) : null}
          {message ? <p className={`account-message ${message.kind}`}>{message.text}</p> : null}
        </>
      ) : null}
    </div>
  );
}
