import type { RemoteDevice } from "@shared/account";
import {
  canConnectToDevice,
  deviceConnectButtonLabel,
  devicePlatformIcon,
  remoteDeviceConnectionClass,
  remoteDeviceConnectionLabel,
  remoteDeviceDetail
} from "./accountRemoteShared";

export interface RemoteDeviceListProps {
  devices: RemoteDevice[];
  localDeviceID?: number | null;
  connectingDeviceId?: number | null;
  onConnectDevice?: (deviceId: number) => void;
  disabled?: boolean;
}

export function RemoteDeviceList({
  devices,
  localDeviceID = null,
  connectingDeviceId = null,
  onConnectDevice,
  disabled = false
}: RemoteDeviceListProps) {
  if (devices.length === 0) {
    return <p className="account-empty">暂无设备。登录后会自动注册本机，也可以手动刷新设备列表。</p>;
  }

  return (
    <div className="account-device-list">
      {devices.map((remoteDevice) => {
        const PlatformIcon = devicePlatformIcon(remoteDevice);
        return (
          <div className="account-device-row" key={remoteDevice.id}>
            <span className={`device-online-dot ${remoteDevice.online ? "online" : ""}`} aria-hidden="true" />
            <span className="account-device-row-icon" aria-hidden="true">
              <PlatformIcon size={17} />
            </span>
            <div className="account-device-row-body">
              <b>{remoteDevice.deviceName}</b>
              <span>{remoteDeviceDetail(remoteDevice, localDeviceID)}</span>
            </div>
            <div className="account-device-row-action">
              {canConnectToDevice(remoteDevice, localDeviceID) ? (
                <button
                  type="button"
                  className="account-remote-connect-button"
                  disabled={disabled || !onConnectDevice || connectingDeviceId === remoteDevice.id}
                  onClick={() => onConnectDevice?.(remoteDevice.id)}
                >
                  {connectingDeviceId === remoteDevice.id ? "连接中…" : deviceConnectButtonLabel(remoteDevice)}
                </button>
              ) : (
                <small className={remoteDeviceConnectionClass(remoteDevice, localDeviceID)}>
                  {remoteDeviceConnectionLabel(remoteDevice, localDeviceID)}
                </small>
              )}
            </div>
          </div>
        );
      })}
    </div>
  );
}
