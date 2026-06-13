import type { LucideIcon } from "lucide-react";
import { Laptop, Monitor, Smartphone } from "lucide-react";
import type { RemoteConnectResult, RemoteDevice } from "@shared/account";
import type { AccountRemoteConnectionStatus } from "../../stores/accountStore";

export function devicePlatformIcon(device: RemoteDevice): LucideIcon {
  const platform = `${device.platform ?? ""} ${device.deviceType ?? ""}`.toLowerCase();
  if (platform.includes("android") || platform.includes("ios") || platform.includes("iphone") || platform.includes("mobile")) {
    return Smartphone;
  }
  if (platform.includes("windows")) {
    return Monitor;
  }
  return Laptop;
}

export function hasDirectEndpoint(device: RemoteDevice): boolean {
  return Boolean(device.lanEndpoint && device.transientToken?.trim());
}

export function canConnectToDevice(device: RemoteDevice, localDeviceID?: number | null): boolean {
  if (localDeviceID === device.id) {
    return false;
  }
  return device.remoteEnabled && device.status === "active";
}

export function deviceConnectButtonLabel(device: RemoteDevice): string {
  return hasDirectEndpoint(device) ? "连接" : "请求连接";
}

export function remoteDeviceDetail(device: RemoteDevice, localDeviceID?: number | null): string {
  const parts = [
    device.platform ?? "unknown",
    device.online ? "在线" : "离线"
  ];
  if (localDeviceID === device.id) {
    parts.push("本机设备");
  } else if (hasDirectEndpoint(device)) {
    parts.push("局域网可连接");
  } else if (canConnectToDevice(device, localDeviceID)) {
    parts.push("信令可请求");
  }
  if (device.lastSeenAt) {
    parts.push(`上次在线 ${device.lastSeenAt}`);
  }
  return parts.join(" · ");
}

export function remoteDeviceConnectionLabel(device: RemoteDevice, localDeviceID?: number | null): string {
  if (localDeviceID === device.id) {
    return "本机";
  }
  if (!device.remoteEnabled) {
    return "远程关闭";
  }
  if (!device.online) {
    return "离线";
  }
  if (hasDirectEndpoint(device)) {
    return "局域网可连接";
  }
  return "信令可请求";
}

export function remoteDeviceConnectionClass(device: RemoteDevice, localDeviceID?: number | null): string {
  if (localDeviceID === device.id) {
    return "local";
  }
  if (device.remoteEnabled && device.status === "active") {
    return hasDirectEndpoint(device) ? "lan-ready" : "available";
  }
  return "";
}

export function connectionStatusLabel(status: AccountRemoteConnectionStatus | string): string {
  switch (status) {
    case "connecting":
      return "连接中";
    case "connected":
      return "已连接";
    case "reconnecting":
      return "重连中";
    case "closed":
      return "已关闭";
    case "error":
      return "异常";
    case "idle":
    default:
      return "空闲";
  }
}

export function signalingStatusText(status: AccountRemoteConnectionStatus | string): string | null {
  switch (status) {
    case "connecting":
    case "reconnecting":
      return "信令通道连接中。";
    case "connected":
      return "信令通道已连接。";
    case "error":
      return "信令通道异常，请检查网络后重试。";
    case "closed":
      return "信令通道已关闭。";
    default:
      return null;
  }
}

export function formatDeviceCode(value: string): string {
  return value.replace(/\s+/g, "").replace(/(.{4})/g, "$1-").replace(/-$/, "");
}

export function deviceCodeFallback(hint: string | null, hasDeviceCode?: boolean): string {
  if (hint) {
    return `仅有尾号 ****-${hint}，请重置后显示完整设备码`;
  }
  return hasDeviceCode ? "已保存，请读取或重置后显示完整设备码" : "未生成";
}

export function formatConnectResult(result: RemoteConnectResult): string {
  const transportLabel = result.transport === "lan"
    ? "局域网"
    : result.transport === "tunnel"
      ? "跨网通道"
      : "公网";
  const detail = result.transport === "lan"
    ? `${result.host}:${result.port}`
    : result.message ?? (result.connectionId ? `连接 #${result.connectionId}` : "");
  return `已连接 · ${transportLabel}${detail ? `（${detail}）` : ""}`;
}

export function transportBadgeLabel(transport: RemoteConnectResult["transport"]): string {
  switch (transport) {
    case "lan":
      return "局域网直连";
    case "tunnel":
      return "跨网通道";
    case "public":
      return "公网端口直连";
    default:
      return transport;
  }
}
