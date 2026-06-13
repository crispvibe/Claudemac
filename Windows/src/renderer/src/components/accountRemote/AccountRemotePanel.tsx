import { Radio, ShieldCheck, Smartphone, UserRound } from "lucide-react";
import type { RemoteConnectResult } from "@shared/account";
import type { AccountRemoteViewState } from "../../stores/accountStore";
import { connectionStatusLabel } from "./accountRemoteShared";
import { RemoteDeviceList } from "./RemoteDeviceList";

export interface AccountRemotePanelProps {
  state: AccountRemoteViewState;
  onLogin?: () => void;
  onRefreshDevices?: () => void;
  onConnectDevice?: (deviceId: number) => Promise<RemoteConnectResult | void>;
  connectingDeviceId?: number | null;
}

export function AccountRemotePanel({
  state,
  onLogin,
  onRefreshDevices,
  onConnectDevice,
  connectingDeviceId = null
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
        <SummaryItem icon={<ShieldCheck size={17} />} label="本机设备" value={deviceLabel} />
        <SummaryItem icon={<Radio size={17} />} label="信令状态" value={connectionStatusLabel(state.connectionStatus)} />
        <SummaryItem
          icon={<Smartphone size={17} />}
          label="在线设备"
          value={`${state.devices.filter((item) => item.online).length} 台`}
        />
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
          <RemoteDeviceList
            devices={state.devices}
            localDeviceID={state.device?.deviceID}
            connectingDeviceId={connectingDeviceId}
            disabled={!onConnectDevice}
            onConnectDevice={onConnectDevice ? (deviceId) => void onConnectDevice(deviceId) : undefined}
          />
        )}
      </div>

      {state.activeConnection ? (
        <div className="remote-connection-banner compact">
          <span className={`remote-transport-badge ${state.activeConnection.transport}`}>
            {state.activeConnection.transport === "lan" ? "局域网" : state.activeConnection.transport === "tunnel" ? "跨网" : "公网"}
          </span>
          <div>
            <strong>
              {state.activeConnection.transport === "lan"
                ? `${state.activeConnection.host}:${state.activeConnection.port}`
                : `连接 #${state.activeConnection.connectionId ?? "?"}`}
            </strong>
          </div>
        </div>
      ) : null}

      {state.lastError ? <p className="account-remote-error">{state.lastError}</p> : null}
    </section>
  );
}

function SummaryItem({ icon, label, value }: { icon: React.ReactNode; label: string; value: string }) {
  return (
    <div className="account-remote-summary-item">
      {icon}
      <span>{label}</span>
      <strong>{value}</strong>
    </div>
  );
}
