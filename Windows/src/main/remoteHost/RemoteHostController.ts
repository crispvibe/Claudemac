// RemoteHostController（Windows host 主进程编排）—— 对应 Mac 的
// `RemoteChatServerController` + `RemoteChatBridge` 的主进程侧职责。
//
// 职责：
//   1. 持久化 host 配置（enabled / port 存 JSON，token 存 CredentialStore）。
//   2. 持有 PanelStateBroadcaster：渲染进程推来的 snapshot 经 ingest 得到 envelope
//      后调 server.broadcast()。
//   3. 管理 RemoteHostServer 生命周期（enable/disable、token 重置）。
//   4. 实现 RemoteHostServerDelegate：把手机命令通过 IPC 转发到渲染进程并等结果。
//   5. 局域网地址发布：周期把 内网IP+端口+短期token 上报后端（对应 LanTokenPublisher）。

import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { randomBytes, randomUUID } from "node:crypto";
import path from "node:path";

import { CredentialStore, CredentialStoreUnavailableError } from "../security/credentialStore.js";
import { localLanIPv4 } from "../remoteConnect/LanSubnetProbe.js";
import { PanelStateBroadcaster, type ReplayPayload } from "./PanelStateBroadcaster.js";
import {
  RemoteHostServer,
  type RemoteHostCommandDispatch,
  type RemoteHostServerDelegate
} from "./RemoteHostServer.js";
import {
  RemoteTunnelResponder,
  type TunnelLanOffer,
  type TunnelResponderSignaling
} from "./RemoteTunnelResponder.js";
import {
  RemoteWebRTCResponder,
  type WebRTCIceServer,
  type WebRTCPeerFactory,
  type WebRTCResponderSignaling
} from "./RemoteWebRTCResponder.js";
import type {
  RemoteHostApplyCommandRequest,
  RemoteHostCommandResult,
  RemoteHostStatus
} from "../../shared/ipc.js";
import type { CommandAck, PanelStateSnapshot, RemoteCommand } from "../../shared/remoteProtocol.js";

export const DEFAULT_REMOTE_HOST_PORT = 18765;
const COMMAND_TIMEOUT_MS = 15_000;
const LAN_PUBLISH_INTERVAL_MS = 15_000;
const LAN_TOKEN_TTL_MS = 120_000;

const TOKEN_CREDENTIAL_NAMESPACE = "remote-host";
const TOKEN_CREDENTIAL_KEY = "host-token";

interface PersistedHostConfig {
  enabled: boolean;
  port: number;
}

/** 局域网发布所需的账号/设备依赖（由 main 注入，复用现有 account 子系统）。 */
export interface RemoteHostLanPublisher {
  /** 当前已登录且未过期的 accessToken；未登录抛错。 */
  requireAccessToken: () => Promise<string>;
  /** 本机已注册的 deviceID；未注册返回 null。 */
  currentDeviceId: () => Promise<number | null>;
  publishLanToken: (
    deviceId: number,
    input: { ip: string; port: number; transientToken: string; expiresAt: number },
    accessToken: string
  ) => Promise<void>;
}

/** 跨网隧道（二期）依赖：复用全局 SignalingClient，并在需要时尝试启动信令。 */
export interface RemoteHostTunnelDeps {
  signaling: TunnelResponderSignaling;
  /** 已登录时尽力启动信令（注册设备由账号子系统负责），未登录静默忽略。 */
  ensureStarted?: () => void | Promise<void>;
}

/** WebRTC P2P（三期/可选）依赖：复用信令 relay 通道，按 connectionId 拉取 ICE 配置。 */
export interface RemoteHostWebRTCDeps {
  signaling: WebRTCResponderSignaling;
  iceServers: (connectionId: number) => Promise<WebRTCIceServer[]>;
  /** 可注入的 peer 工厂（测试用）；缺省由 responder 动态加载 werift。 */
  createPeer?: WebRTCPeerFactory;
}

export interface RemoteHostControllerDeps {
  userDataDir: string;
  /** 把命令转发到渲染进程执行。返回 false 表示当前没有可用渲染进程。 */
  requestApplyCommand: (payload: RemoteHostApplyCommandRequest) => boolean;
  /** 把最新状态推给渲染进程 / 设置页。 */
  publishStatus: (status: RemoteHostStatus) => void;
  lan?: RemoteHostLanPublisher;
  tunnel?: RemoteHostTunnelDeps;
  webrtc?: RemoteHostWebRTCDeps;
}

interface PendingCommand {
  resolve: (result: RemoteHostCommandResult) => void;
  reject: (error: Error) => void;
  timer: NodeJS.Timeout;
}

export class RemoteHostController implements RemoteHostServerDelegate {
  private readonly broadcaster = new PanelStateBroadcaster();
  private readonly credentials = new CredentialStore(TOKEN_CREDENTIAL_NAMESPACE);
  private readonly pending = new Map<string, PendingCommand>();
  private server: RemoteHostServer | null = null;
  private responder: RemoteTunnelResponder | null = null;
  private webrtcResponder: RemoteWebRTCResponder | null = null;
  private enabled = false;
  private port = DEFAULT_REMOTE_HOST_PORT;
  private token = "";
  private lastError: string | null = null;
  private lanPublishTimer: NodeJS.Timeout | null = null;
  private initialized = false;

  constructor(private readonly deps: RemoteHostControllerDeps) {}

  private get configPath(): string {
    return path.join(this.deps.userDataDir, "remote-host.json");
  }

  /** 加载持久化配置，必要时生成 token；若 enabled 则启动服务。 */
  async init(): Promise<void> {
    if (this.initialized) return;
    this.initialized = true;
    const config = await this.loadConfig();
    this.enabled = config.enabled;
    this.port = config.port;
    this.token = await this.loadOrCreateToken();
    if (this.enabled) {
      await this.startServer().catch((error: unknown) => {
        this.lastError = error instanceof Error ? error.message : String(error);
      });
    }
    this.emitStatus();
  }

  getStatus(): RemoteHostStatus {
    const lanIp = this.server?.isLanListening ? localLanIPv4() : null;
    return {
      enabled: this.enabled,
      running: this.server?.isRunning ?? false,
      port: this.port,
      token: this.token,
      lanAddress: lanIp ? `${lanIp}:${this.port}` : null,
      activeConnectionCount: this.server?.activeConnectionCount ?? 0,
      lastError: this.lastError
    };
  }

  async setEnabled(enabled: boolean): Promise<RemoteHostStatus> {
    if (this.enabled === enabled && (this.server?.isRunning ?? false) === enabled) {
      return this.getStatus();
    }
    // 先启停成功，再落库 enabled：避免启动失败（如端口占用）却把 enabled=true 持久化。
    if (enabled) {
      await this.startServer();
      this.enabled = true;
    } else {
      await this.stopServer();
      this.enabled = false;
    }
    await this.persistConfig();
    this.emitStatus();
    return this.getStatus();
  }

  async resetToken(): Promise<RemoteHostStatus> {
    this.token = generateToken();
    await this.saveToken(this.token);
    if (this.server) {
      await this.stopServer();
      await this.startServer();
    }
    this.emitStatus();
    return this.getStatus();
  }

  /** 渲染进程推来的 snapshot：标记 revision / diff，并按 focus 广播。 */
  ingestSnapshot(snapshot: PanelStateSnapshot): void {
    const envelope = this.broadcaster.ingest(snapshot);
    this.server?.broadcast(envelope);
  }

  /** 渲染进程执行完命令后回传结果，结算对应的 pending。 */
  resolveCommandResult(result: RemoteHostCommandResult): void {
    const entry = this.pending.get(result.requestId);
    if (!entry) return;
    clearTimeout(entry.timer);
    this.pending.delete(result.requestId);
    entry.resolve(result);
  }

  async shutdown(): Promise<void> {
    this.stopLanPublishing();
    for (const entry of this.pending.values()) {
      clearTimeout(entry.timer);
      entry.reject(new Error("controller shutting down"));
    }
    this.pending.clear();
    await this.stopServer();
  }

  // MARK: - RemoteHostServerDelegate

  async applyCommand(command: RemoteCommand, focusedSessionId: string | null): Promise<RemoteHostCommandDispatch> {
    const requestId = randomUUID();
    const resultPromise = new Promise<RemoteHostCommandResult>((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(requestId);
        reject(new Error("命令处理超时。"));
      }, COMMAND_TIMEOUT_MS);
      this.pending.set(requestId, { resolve, reject, timer });
    });

    const delivered = this.deps.requestApplyCommand({ requestId, focusedSessionId, command });
    if (!delivered) {
      const entry = this.pending.get(requestId);
      if (entry) {
        clearTimeout(entry.timer);
        this.pending.delete(requestId);
      }
      throw new Error("渲染进程暂不可用。");
    }

    const result = await resultPromise;
    return {
      ack: result.ack,
      shouldUpdateFocusedSessionId: result.shouldUpdateFocusedSessionId,
      newFocusedSessionId: result.newFocusedSessionId ?? null,
      shouldPushSnapshotForFocus: result.shouldPushSnapshotForFocus
    } satisfies RemoteHostCommandDispatch;
  }

  replayPayload(sessionId: string | null, lastRevision: number | null): ReplayPayload {
    return this.broadcaster.replayPayload(sessionId, lastRevision);
  }

  snapshotFor(sessionId: string | null): PanelStateSnapshot | null {
    return this.broadcaster.snapshotFor(sessionId);
  }

  // MARK: - server lifecycle

  private async startServer(): Promise<void> {
    if (this.server) return;
    if (!this.token) this.token = await this.loadOrCreateToken();
    const server = new RemoteHostServer(
      { port: this.port, token: this.token, bindLAN: true },
      this,
      {
        onConnectionsChanged: () => this.emitStatus(),
        onError: (error) => {
          this.lastError = error.message;
          this.emitStatus();
        }
      }
    );
    // 先挂上 server，使 onError 回调 / 后续编排可见；start 仅在缺 token 时抛错。
    this.server = server;
    try {
      await server.start();
    } catch (error) {
      this.server = null;
      this.lastError = error instanceof Error ? error.message : String(error);
      throw error;
    }
    // LAN 绑定失败不致命：记录错误但隧道 / WebRTC 仍随后启动。
    this.lastError = server.lastErrorMessage;
    this.startLanPublishing();
    this.startTunnelResponder(server);
    this.startWebRTCResponder(server);
  }

  private async stopServer(): Promise<void> {
    this.stopLanPublishing();
    this.stopTunnelResponder();
    this.stopWebRTCResponder();
    const server = this.server;
    this.server = null;
    if (server) await server.stop();
  }

  // MARK: - tunnel responder（二期跨网）

  private startTunnelResponder(server: RemoteHostServer): void {
    if (!this.deps.tunnel || this.responder) return;
    const responder = new RemoteTunnelResponder({
      signaling: this.deps.tunnel.signaling,
      server,
      lanOffer: () => this.buildLanOffer()
    });
    responder.attach();
    this.responder = responder;
    // 已登录则尽力把信令拉起，让手机的入站隧道能被路由进来。
    void Promise.resolve(this.deps.tunnel.ensureStarted?.()).catch(() => undefined);
  }

  private stopTunnelResponder(): void {
    this.responder?.detach();
    this.responder = null;
  }

  // MARK: - webrtc responder（三期/可选）

  private startWebRTCResponder(server: RemoteHostServer): void {
    if (!this.deps.webrtc || this.webrtcResponder) return;
    const responder = new RemoteWebRTCResponder({
      signaling: this.deps.webrtc.signaling,
      server,
      iceServers: this.deps.webrtc.iceServers,
      createPeer: this.deps.webrtc.createPeer
    });
    responder.attach();
    this.webrtcResponder = responder;
  }

  private stopWebRTCResponder(): void {
    this.webrtcResponder?.detach();
    this.webrtcResponder = null;
  }

  /** 为隧道升级生成一份 LAN offer：登记短期 token 后返回内网地址。 */
  private buildLanOffer(): TunnelLanOffer | null {
    const server = this.server;
    if (!server?.isLanListening) return null;
    const ip = localLanIPv4();
    if (!ip) return null;
    const token = generateToken();
    server.setTransientToken(token, Date.now() + LAN_TOKEN_TTL_MS);
    return { ip, port: this.port, token };
  }

  // MARK: - LAN publishing

  private startLanPublishing(): void {
    if (!this.deps.lan || this.lanPublishTimer) return;
    void this.publishLanOnce();
    this.lanPublishTimer = setInterval(() => void this.publishLanOnce(), LAN_PUBLISH_INTERVAL_MS);
  }

  private stopLanPublishing(): void {
    if (this.lanPublishTimer) {
      clearInterval(this.lanPublishTimer);
      this.lanPublishTimer = null;
    }
  }

  private async publishLanOnce(): Promise<void> {
    const lan = this.deps.lan;
    const server = this.server;
    if (!lan || !server?.isLanListening) return;
    const ip = localLanIPv4();
    if (!ip) return;
    try {
      const deviceId = await lan.currentDeviceId();
      if (!deviceId) return;
      const accessToken = await lan.requireAccessToken();
      const transientToken = generateToken();
      const expiresAt = Date.now() + LAN_TOKEN_TTL_MS;
      // 先在本机登记短期 token，确保后端发布后手机用它一定能连入。
      server.setTransientToken(transientToken, expiresAt);
      await lan.publishLanToken(deviceId, { ip, port: this.port, transientToken, expiresAt }, accessToken);
    } catch {
      // 未登录 / 网络失败时静默；同 WiFi 仍可通过信令协商 LAN 地址（二期）。
    }
  }

  // MARK: - persistence

  private emitStatus(): void {
    this.deps.publishStatus(this.getStatus());
  }

  private async loadConfig(): Promise<PersistedHostConfig> {
    try {
      const raw = await readFile(this.configPath, "utf8");
      const parsed = JSON.parse(raw) as Partial<PersistedHostConfig>;
      const port = typeof parsed.port === "number" && parsed.port >= 1 && parsed.port <= 65535
        ? parsed.port
        : DEFAULT_REMOTE_HOST_PORT;
      return { enabled: parsed.enabled === true, port };
    } catch {
      return { enabled: false, port: DEFAULT_REMOTE_HOST_PORT };
    }
  }

  private async persistConfig(): Promise<void> {
    const config: PersistedHostConfig = { enabled: this.enabled, port: this.port };
    try {
      await mkdir(path.dirname(this.configPath), { recursive: true });
      const tmp = `${this.configPath}.tmp`;
      await writeFile(tmp, `${JSON.stringify(config, null, 2)}\n`, "utf8");
      await rename(tmp, this.configPath);
    } catch {
      // 配置持久化失败不致命（下次仍可用默认值）。
    }
  }

  private async loadOrCreateToken(): Promise<string> {
    try {
      const existing = await this.credentials.readSecret(TOKEN_CREDENTIAL_KEY);
      if (existing) return existing;
    } catch {
      // 读不出来就重新生成
    }
    const token = generateToken();
    await this.saveToken(token);
    return token;
  }

  private async saveToken(token: string): Promise<void> {
    try {
      await this.credentials.writeSecret(TOKEN_CREDENTIAL_KEY, token);
    } catch (error) {
      if (!(error instanceof CredentialStoreUnavailableError)) {
        // 其他写入错误也只记录，token 仍在内存可用
      }
    }
  }
}

function generateToken(): string {
  return randomBytes(24).toString("base64url");
}
