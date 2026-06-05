import { Monitor, Radio, ShieldCheck, Smartphone, UserRound } from "lucide-react";
import type { ReactNode } from "react";
import type { RemoteDevice } from "@shared/account";
import type { AccountRemoteViewState } from "../../stores/accountStore";

export interface AccountRemotePanelProps {
  state: AccountRemoteViewState;
  onLogin?: () => void;
  onRefreshDevices?: () => void;
}

export function AccountRemotePanel({
  state,
  onLogin,
  onRefreshDevices
}: AccountRemotePanelProps) {
  const accountLabel = state.account.displayAccount ?? "未登录";
  const deviceLabel = state.device?.deviceName ?? "未注册本机";

  return (
    <section className="account-remote-panel" aria-label="账号与远程设备">
      <header className="account-remote-header">
        <div>
          <UserRound size={18} />
          <span>{accountLabel}</span>
        </div>
        <button type="button" onClick={onLogin} disabled={!onLogin}>
          登录
        </button>
      </header>

      <div className="account-remote-summary">
        <SummaryItem icon={<Monitor size={17} />} label="本机设备" value={deviceLabel} />
        <SummaryItem icon={<ShieldCheck size={17} />} label="账号状态" value={state.account.status} />
        <SummaryItem icon={<Radio size={17} />} label="信令状态" value={state.connectionStatus} />
      </div>

      <div className="account-remote-device-list">
        <div className="account-remote-list-header">
          <span>远程设备</span>
          <button type="button" onClick={onRefreshDevices} disabled={!onRefreshDevices}>
            刷新
          </button>
        </div>
        {state.devices.length === 0 ? (
          <p className="account-remote-empty">暂无可连接设备</p>
        ) : (
          state.devices.map((device) => (
            <div className="account-remote-device-row" key={device.id}>
              <Smartphone size={16} />
              <div>
                <span>{device.deviceName}</span>
                <em>{device.platform ?? "unknown"} · {device.online ? "在线" : "离线"}</em>
              </div>
              <small className={remoteDeviceConnectionClass(device, state.device?.deviceID)}>{remoteDeviceConnectionLabel(device, state.device?.deviceID)}</small>
            </div>
          ))
        )}
      </div>

      {state.lastError ? <p className="account-remote-error">{state.lastError}</p> : null}
    </section>
  );
}

function SummaryItem({ icon, label, value }: { icon: ReactNode; label: string; value: string }) {
  return (
    <div className="account-remote-summary-item">
      {icon}
      <span>{label}</span>
      <strong>{value}</strong>
    </div>
  );
}

function remoteDeviceConnectionLabel(device: RemoteDevice, localDeviceID?: number | null): string {
  if (localDeviceID === device.id) {
    return "本机";
  }
  if (!device.remoteEnabled) {
    return "远程关闭";
  }
  if (!device.online) {
    return "离线";
  }
  return "连接未接入";
}

function remoteDeviceConnectionClass(device: RemoteDevice, localDeviceID?: number | null): string {
  if (localDeviceID === device.id) {
    return "local";
  }
  if (device.online && device.remoteEnabled) {
    return "unavailable";
  }
  return "";
}
