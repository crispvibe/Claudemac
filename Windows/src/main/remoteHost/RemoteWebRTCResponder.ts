// RemoteWebRTCResponder（Windows host WebRTC P2P 应答端，三期/可选）—— 对应 Mac 的
// `RemoteWebRTCBridge.swift` + `DeviceProvisioningViewModel` 的 host 侧 WebRTC 编排。
//
// 角色：手机是 offerer（创建 data channel + 发 offer），Windows host 是 answerer。
// 协商经信令 `relay`（offer/answer/candidate）；建连后 data channel 收发的文本帧与
// LAN WS / 隧道完全一致，复用 `RemoteHostServer` 的虚拟连接（命令/广播同一管道）。
//
// 数据流：
//   手机 --relay(offer/candidate)--> 信令 --> SignalingClient(入站 relay) --> 本类
//     --> 创建 answerer peer，回 relay(answer/candidate)
//   建连后：data channel <-> RemoteHostServer 虚拟连接（deliverFrame / broadcast）
//
// werift（纯 TS WebRTC）通过动态 import 加载：加载失败时本责任链静默不可用，
// 不影响 LAN / 隧道两条通路。

import type {
  InboundRelayEvent,
  SignalingPayload
} from "../signaling/SignalingClient.js";
import type {
  HostConnection,
  HostConnectionSink,
  RemoteHostServer
} from "./RemoteHostServer.js";

/** ICE 服务器配置（来自后端 `remote/ice-config`）。 */
export interface WebRTCIceServer {
  urls: string[];
  username?: string;
  credential?: string;
}

/** data channel 抽象（werift / 测试假实现共用）。 */
export interface WebRTCDataChannelLike {
  readonly readyState: string;
  send(text: string): void;
  close(): void;
  onMessage(listener: (text: string) => void): void;
  onStateChange(listener: (state: string) => void): void;
}

/** peer connection 抽象（werift / 测试假实现共用）。 */
export interface WebRTCPeerLike {
  setRemoteDescription(description: { type: string; sdp: string }): Promise<void>;
  createAnswer(): Promise<{ type: string; sdp: string }>;
  setLocalDescription(description: { type: string; sdp: string }): Promise<void>;
  localDescription(): { type: string; sdp: string } | null;
  addIceCandidate(candidate: { candidate: string; sdpMid?: string | null; sdpMLineIndex?: number | null }): Promise<void>;
  onIceCandidate(listener: (candidate: { candidate: string; sdpMid?: string; sdpMLineIndex?: number } | null) => void): void;
  onDataChannel(listener: (channel: WebRTCDataChannelLike) => void): void;
  onConnectionStateChange(listener: (state: string) => void): void;
  close(): Promise<void> | void;
}

/** peer 工厂：注入以便测试；默认用 werift。 */
export type WebRTCPeerFactory = (iceServers: WebRTCIceServer[]) => Promise<WebRTCPeerLike>;

export interface WebRTCResponderSignaling {
  setInboundRelayHandler(handler: (event: InboundRelayEvent) => void): void;
  clearInboundRelayHandler(): void;
  relay(connectionId: number, toDeviceId: number, payload: SignalingPayload): boolean;
}

export interface RemoteWebRTCResponderDeps {
  signaling: WebRTCResponderSignaling;
  server: RemoteHostServer;
  /** 拉取某 connection 的 ICE 配置（含短期 TURN 凭据）。 */
  iceServers: (connectionId: number) => Promise<WebRTCIceServer[]>;
  /** peer 工厂；缺省用 werift 动态加载。 */
  createPeer?: WebRTCPeerFactory;
}

/** data channel 未在此时限内打开则判定打洞失败，关闭并释放 peer（对应 Mac 的 20s）。 */
const DATA_CHANNEL_OPEN_TIMEOUT_MS = 30_000;

function payloadKind(payload: SignalingPayload): string {
  const value = payload.type ?? (payload as { kind?: unknown }).kind;
  return typeof value === "string" ? value.toLowerCase() : "";
}

interface BridgeDeps {
  signaling: WebRTCResponderSignaling;
  server: RemoteHostServer;
  iceServers: (connectionId: number) => Promise<WebRTCIceServer[]>;
  createPeer: WebRTCPeerFactory;
  onClosed: (connectionId: number) => void;
}

/** 单个 WebRTC 连接的 answerer 状态机。 */
class RemoteWebRTCBridge {
  private peer: WebRTCPeerLike | null = null;
  private connection: HostConnection | null = null;
  private channel: WebRTCDataChannelLike | null = null;
  private didSetRemoteDescription = false;
  private readonly pendingPayloads: SignalingPayload[] = [];
  private readonly pendingCandidates: Array<{ candidate: string; sdpMid?: string | null; sdpMLineIndex?: number | null }> = [];
  private flushing = false;
  private closed = false;
  private openTimer: ReturnType<typeof setTimeout> | null = null;

  constructor(
    private readonly connectionId: number,
    private readonly peerDeviceId: number,
    private readonly deps: BridgeDeps
  ) {}

  async start(): Promise<void> {
    let iceServers: WebRTCIceServer[] = [];
    try {
      iceServers = await this.deps.iceServers(this.connectionId);
    } catch {
      iceServers = [];
    }
    if (this.closed) return;
    let peer: WebRTCPeerLike;
    try {
      peer = await this.deps.createPeer(iceServers);
    } catch {
      this.close();
      return;
    }
    if (this.closed) {
      void Promise.resolve(peer.close()).catch(() => undefined);
      return;
    }
    this.peer = peer;
    // 打洞兜底：若 data channel 始终不 open（ICE 卡死且不报 failed），超时释放 peer，避免泄漏。
    this.openTimer = setTimeout(() => {
      if (!this.connection && !this.closed) this.close();
    }, DATA_CHANNEL_OPEN_TIMEOUT_MS);
    peer.onIceCandidate((candidate) => {
      if (candidate) this.relayCandidate(candidate);
    });
    peer.onDataChannel((channel) => this.adoptChannel(channel));
    peer.onConnectionStateChange((state) => {
      if (state === "failed" || state === "closed" || state === "disconnected") this.close();
    });
    void this.flushPayloads();
  }

  receiveRelayPayload(payload: SignalingPayload): void {
    if (this.closed) return;
    this.pendingPayloads.push(payload);
    if (this.peer) void this.flushPayloads();
  }

  close(): void {
    if (this.closed) return;
    this.closed = true;
    if (this.openTimer) {
      clearTimeout(this.openTimer);
      this.openTimer = null;
    }
    if (this.connection) {
      this.deps.server.detachVirtualConnection(this.connection);
      this.connection = null;
    }
    try {
      this.channel?.close();
    } catch {
      // ignore
    }
    this.channel = null;
    const peer = this.peer;
    this.peer = null;
    if (peer) void Promise.resolve(peer.close()).catch(() => undefined);
    this.deps.onClosed(this.connectionId);
  }

  // MARK: - 协商

  private async flushPayloads(): Promise<void> {
    if (this.flushing) return;
    this.flushing = true;
    try {
      while (this.peer && !this.closed && this.pendingPayloads.length > 0) {
        const payload = this.pendingPayloads.shift();
        if (!payload) break;
        await this.processPayload(payload);
      }
    } finally {
      this.flushing = false;
    }
  }

  private async processPayload(payload: SignalingPayload): Promise<void> {
    const peer = this.peer;
    if (!peer || this.closed) return;
    switch (payloadKind(payload)) {
      case "offer": {
        const sdp = payload.sdp;
        if (!sdp) return;
        try {
          await peer.setRemoteDescription({ type: "offer", sdp });
          this.didSetRemoteDescription = true;
          this.drainPendingCandidates();
          const answer = await peer.createAnswer();
          await peer.setLocalDescription(answer);
          const local = peer.localDescription() ?? answer;
          this.relayAnswer(local.sdp);
        } catch {
          this.close();
        }
        break;
      }
      case "candidate": {
        const candidate = payload.candidate;
        if (typeof candidate !== "string" || candidate.length === 0) return;
        const init = {
          candidate,
          sdpMid: payload.sdpMid ?? null,
          sdpMLineIndex: payload.sdpMLineIndex ?? null
        };
        if (!this.didSetRemoteDescription) {
          this.pendingCandidates.push(init);
          return;
        }
        await peer.addIceCandidate(init).catch(() => undefined);
        break;
      }
      default:
        // answer / failed：host 作为 answerer 不处理。
        break;
    }
  }

  private drainPendingCandidates(): void {
    const peer = this.peer;
    if (!peer) return;
    const candidates = this.pendingCandidates.splice(0, this.pendingCandidates.length);
    for (const candidate of candidates) {
      void peer.addIceCandidate(candidate).catch(() => undefined);
    }
  }

  private relayAnswer(sdp: string): void {
    this.deps.signaling.relay(this.connectionId, this.peerDeviceId, { type: "answer", sdp } as SignalingPayload);
  }

  private relayCandidate(candidate: { candidate: string; sdpMid?: string; sdpMLineIndex?: number }): void {
    this.deps.signaling.relay(this.connectionId, this.peerDeviceId, {
      type: "candidate",
      candidate: candidate.candidate,
      sdpMid: candidate.sdpMid,
      sdpMLineIndex: candidate.sdpMLineIndex
    } as SignalingPayload);
  }

  // MARK: - data channel

  private adoptChannel(channel: WebRTCDataChannelLike): void {
    if (this.closed) return;
    this.channel = channel;
    channel.onMessage((text) => {
      const connection = this.connection;
      if (connection) this.deps.server.deliverFrame(connection, text);
    });
    channel.onStateChange((state) => {
      if (state === "open") this.handleChannelOpen();
      else if (state === "closed") this.close();
    });
    if (channel.readyState === "open") this.handleChannelOpen();
  }

  private handleChannelOpen(): void {
    if (this.connection || this.closed) return;
    const channel = this.channel;
    if (!channel) return;
    if (this.openTimer) {
      clearTimeout(this.openTimer);
      this.openTimer = null;
    }
    const sink: HostConnectionSink = {
      send: (text) => channel.send(text),
      isOpen: () => !this.closed && channel.readyState === "open",
      close: () => undefined
    };
    this.connection = this.deps.server.attachVirtualConnection(sink);
  }
}

export class RemoteWebRTCResponder {
  private readonly bridges = new Map<number, RemoteWebRTCBridge>();
  private readonly createPeer: WebRTCPeerFactory;
  private attached = false;

  constructor(private readonly deps: RemoteWebRTCResponderDeps) {
    this.createPeer = deps.createPeer ?? createWeriftPeer;
  }

  attach(): void {
    if (this.attached) return;
    this.attached = true;
    this.deps.signaling.setInboundRelayHandler((event) => this.handleRelay(event));
  }

  detach(): void {
    if (!this.attached) return;
    this.attached = false;
    this.deps.signaling.clearInboundRelayHandler();
    for (const bridge of [...this.bridges.values()]) {
      bridge.close();
    }
    this.bridges.clear();
  }

  get activePeerCount(): number {
    return this.bridges.size;
  }

  private handleRelay(event: InboundRelayEvent): void {
    if (event.status && event.status !== "accepted") return;
    if (!event.fromDeviceId) return;
    const existing = this.bridges.get(event.connectionId);
    // 只有 offer 能开新连接：candidate/answer 等在没有 offer 时丢弃，避免空转 bridge 与反复重建。
    if (!existing && payloadKind(event.payload) !== "offer") return;
    const bridge = existing ?? this.createBridge(event.connectionId, event.fromDeviceId);
    bridge.receiveRelayPayload(event.payload);
  }

  private createBridge(connectionId: number, peerDeviceId: number): RemoteWebRTCBridge {
    const bridge = new RemoteWebRTCBridge(connectionId, peerDeviceId, {
      signaling: this.deps.signaling,
      server: this.deps.server,
      iceServers: this.deps.iceServers,
      createPeer: this.createPeer,
      onClosed: (id) => this.bridges.delete(id)
    });
    this.bridges.set(connectionId, bridge);
    void bridge.start().catch(() => bridge.close());
    return bridge;
  }
}

/** 缓存 werift 动态加载结果：加载失败时复用被拒 Promise，避免每次连接都重试 import。 */
let weriftModulePromise: Promise<Record<string, unknown>> | null = null;

function loadWerift(): Promise<Record<string, unknown>> {
  if (!weriftModulePromise) {
    weriftModulePromise = import("werift").then((mod) => mod as unknown as Record<string, unknown>);
  }
  return weriftModulePromise;
}

/** 默认 peer 工厂：动态加载 werift（纯 TS WebRTC）。加载/构造失败抛错，由调用方降级。 */
export const createWeriftPeer: WebRTCPeerFactory = async (iceServers) => {
  const moduleImport = await loadWerift();
  const RTCPeerConnection = (moduleImport.RTCPeerConnection
    ?? (moduleImport.default as Record<string, unknown> | undefined)?.RTCPeerConnection) as
    (new (config: unknown) => unknown) | undefined;
  if (typeof RTCPeerConnection !== "function") {
    throw new Error("werift RTCPeerConnection 不可用。");
  }

  // werift 的 iceServers 每项只接受单个 url 字符串，这里把数组展开。
  const flattened: Array<{ urls: string; username?: string; credential?: string }> = [];
  for (const server of iceServers) {
    for (const url of server.urls) {
      const trimmed = url.trim();
      if (!trimmed) continue;
      const entry: { urls: string; username?: string; credential?: string } = { urls: trimmed };
      if (server.username) entry.username = server.username;
      if (server.credential) entry.credential = server.credential;
      flattened.push(entry);
    }
  }

  const pc = new RTCPeerConnection({ iceServers: flattened, iceTransportPolicy: "all" }) as Record<string, any>;

  return {
    setRemoteDescription: (description) => pc.setRemoteDescription(description),
    createAnswer: async () => {
      const answer = await pc.createAnswer();
      return { type: String(answer.type), sdp: String(answer.sdp) };
    },
    setLocalDescription: async (description) => {
      await pc.setLocalDescription(description);
    },
    localDescription: () => {
      const local = pc.localDescription;
      return local ? { type: String(local.type), sdp: String(local.sdp) } : null;
    },
    addIceCandidate: (candidate) => pc.addIceCandidate(candidate),
    onIceCandidate: (listener) => {
      pc.onIceCandidate.subscribe((candidate: any) => {
        listener(candidate
          ? { candidate: candidate.candidate, sdpMid: candidate.sdpMid, sdpMLineIndex: candidate.sdpMLineIndex }
          : null);
      });
    },
    onDataChannel: (listener) => {
      pc.onDataChannel.subscribe((channel: any) => listener(wrapWeriftChannel(channel)));
    },
    onConnectionStateChange: (listener) => {
      pc.connectionStateChange.subscribe((state: any) => listener(String(state)));
    },
    close: () => pc.close()
  } satisfies WebRTCPeerLike;
};

function wrapWeriftChannel(channel: Record<string, any>): WebRTCDataChannelLike {
  return {
    get readyState() {
      return String(channel.readyState);
    },
    send: (text) => channel.send(text),
    close: () => channel.close(),
    onMessage: (listener) => {
      channel.onMessage.subscribe((data: unknown) => {
        const text = typeof data === "string" ? data : Buffer.isBuffer(data) ? data.toString("utf8") : String(data);
        listener(text);
      });
    },
    onStateChange: (listener) => {
      channel.stateChanged.subscribe((state: unknown) => listener(String(state)));
    }
  };
}
