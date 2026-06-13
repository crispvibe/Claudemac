import type { AccountClient } from "../account/AccountClient.js";
import type { DeviceIdentityStore } from "../device/DeviceIdentityStore.js";
import type { SignalingClient } from "../signaling/SignalingClient.js";
import type { RemoteConnectResult, RemoteConnectionAttempt, RemoteDevice } from "../../shared/account.js";
import { discoverHealthHost, lanSubnetPrefix, localLanIPv4 } from "./LanSubnetProbe.js";
import { resolveLanViaSignaling, type LanDirectConfig } from "./LanSignalingResolver.js";

function isPrivateIPv4(host: string): boolean {
  const octets = host.trim().split(".").map((part) => Number.parseInt(part, 10));
  if (octets.length !== 4 || octets.some((value) => Number.isNaN(value) || value < 0 || value > 255)) {
    return false;
  }
  if (octets[0] === 10) return true;
  if (octets[0] === 172 && octets[1] >= 16 && octets[1] <= 31) return true;
  if (octets[0] === 192 && octets[1] === 168) return true;
  return false;
}

function lanConfigFromDevice(device: RemoteDevice | null | undefined): LanDirectConfig | null {
  const endpoint = device?.lanEndpoint;
  const token = device?.transientToken?.trim();
  if (!endpoint || !token || !isPrivateIPv4(endpoint.ip)) return null;
  return { host: endpoint.ip, port: endpoint.port, token, transport: "lan" };
}

function lanConfigFromAttempt(attempt: RemoteConnectionAttempt): LanDirectConfig | null {
  const endpoint = attempt.endpoint;
  const token = attempt.transientToken?.trim();
  if (!endpoint || !token || !isPrivateIPv4(endpoint.ip)) return null;
  return { host: endpoint.ip, port: endpoint.port, token, transport: "lan" };
}

async function healthOk(host: string, port: number): Promise<boolean> {
  try {
    const response = await fetch(`http://${host}:${port}/health`, { signal: AbortSignal.timeout(8_000) });
    return response.ok;
  } catch {
    return false;
  }
}

async function establishDirectLAN(config: LanDirectConfig): Promise<LanDirectConfig> {
  let host = config.host;
  const prefix = lanSubnetPrefix();
  const offeredPrefix = host.split(".").slice(0, 3).join(".");
  if (prefix && offeredPrefix !== prefix) {
    const discovered = await discoverHealthHost(config.port, localLanIPv4());
    if (discovered) host = discovered;
  }
  if (!(await healthOk(host, config.port))) {
    const discovered = await discoverHealthHost(config.port, host);
    if (!discovered) {
      throw new Error(`无法访问电脑地址 ${host}:${config.port}，请确认与目标电脑在同一局域网。`);
    }
    host = discovered;
  }
  if (!(await healthOk(host, config.port))) {
    throw new Error(`无法访问电脑地址 ${host}:${config.port}，请确认与目标电脑在同一局域网。`);
  }
  return { ...config, host };
}

async function waitForSignaling(signalingClient: SignalingClient, timeoutMs = 8_000): Promise<void> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (signalingClient.status === "connected") return;
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error("信令通道连接超时，请确认网络后重试。");
}

async function waitForConnectionDecision(
  accountClient: AccountClient,
  connectionId: number,
  accessToken: string
): Promise<RemoteConnectionAttempt> {
  const delays = [2_000, 3_000, 5_000, 8_000, 10_000];
  for (const delay of delays) {
    await new Promise((resolve) => setTimeout(resolve, delay));
    const connection = await accountClient.connection(connectionId, accessToken);
    if (connection.status !== "pending") return connection;
  }
  throw new Error("等待电脑端确认超时，请确认设备在线后重试。");
}

export class DeviceConnectService {
  constructor(
    private readonly accountClient: AccountClient,
    private readonly deviceIdentityStore: DeviceIdentityStore,
    private readonly signalingClient: SignalingClient
  ) {}

  async connectDevice(deviceId: number, accessToken: string): Promise<RemoteConnectResult> {
    const identity = await this.deviceIdentityStore.loadOrCreateIdentity();
    const fromDeviceId = identity.deviceID;
    if (!fromDeviceId) {
      throw new Error("本机设备尚未注册，请重新登录后再试。");
    }

    let latestDevice = await this.accountClient.device(deviceId, accessToken);
    const tried = new Set<string>();
    let lanFailureMessage: string | null = null;

    const tryLAN = async (config: LanDirectConfig | null): Promise<RemoteConnectResult | null> => {
      if (!config) return null;
      const key = `${config.host}:${config.port}:${config.token}`;
      if (tried.has(key)) return null;
      tried.add(key);
      try {
        const ready = await establishDirectLAN(config);
        return {
          transport: "lan",
          host: ready.host,
          port: ready.port,
          token: ready.token,
          connectionId: null,
          targetDeviceId: deviceId,
          message: null
        };
      } catch (error) {
        if (!lanFailureMessage) {
          lanFailureMessage = error instanceof Error ? error.message : String(error);
        }
        return null;
      }
    };

    if (localLanIPv4()) {
      const preLAN = await tryLAN(lanConfigFromDevice(latestDevice));
      if (preLAN) return preLAN;
    }

    let attempt = await this.accountClient.connect(
      deviceId,
      fromDeviceId,
      identity.deviceUID,
      identity.devicePublicKey,
      accessToken
    );
    if (attempt.status === "pending") {
      const connectionId = attempt.connectionId ?? attempt.id;
      attempt = await waitForConnectionDecision(this.accountClient, connectionId, accessToken);
    }
    if (attempt.status !== "accepted") {
      throw new Error(attempt.reason ?? `连接请求未完成：${attempt.status}`);
    }

    const connectionId = attempt.connectionId ?? attempt.id;
    const targetDeviceId = attempt.toDeviceId ?? deviceId;
    latestDevice = await this.accountClient.device(deviceId, accessToken);

    if (localLanIPv4()) {
      await waitForSignaling(this.signalingClient).catch(() => undefined);
      const signalingLAN = await resolveLanViaSignaling(this.signalingClient, connectionId, targetDeviceId);
      const fromSignaling = await tryLAN(signalingLAN);
      if (fromSignaling) return fromSignaling;
    }

    const fromAttempt = await tryLAN(lanConfigFromAttempt(attempt));
    if (fromAttempt) return fromAttempt;

    const fromDevice = await tryLAN(lanConfigFromDevice(latestDevice));
    if (fromDevice) return fromDevice;

    await waitForSignaling(this.signalingClient);
    if (!this.signalingClient.openTunnel(connectionId, targetDeviceId)) {
      throw new Error("信令通道暂不可用，无法建立远程通道。");
    }

    const fallbackNote = lanFailureMessage
      ? `已改用跨网通道（局域网不可用：${lanFailureMessage}）。`
      : null;

    return {
      transport: "tunnel",
      host: "",
      port: 0,
      token: accessToken,
      connectionId,
      targetDeviceId,
      message: fallbackNote
    };
  }
}
