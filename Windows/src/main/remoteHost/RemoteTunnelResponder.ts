// RemoteTunnelResponder（Windows host 跨网/隧道应答端）—— 对应 Mac 的
// `RemoteTunnelClient.swift`。
//
// 职责：把信令服务器中转过来的「入站隧道」帧喂进与 LAN WS 完全相同的
// command/envelope 管道（复用 `RemoteHostServer` 的虚拟连接），并在开启时下发
// `lan_offer`，让同网手机自动升级到 LAN 直连。
//
// 数据流：
//   手机 --tunnel_open/frame--> 后端信令 --> SignalingClient(入站) --> 本类
//     --> RemoteHostServer.attachVirtualConnection / deliverFrame
//   广播（电脑→手机）：RemoteHostServer.broadcast --> 虚拟连接 sink
//     --> signaling.sendTunnelFrame --> 后端信令 --> 手机

import type {
  HostConnection,
  HostConnectionSink,
  RemoteHostServer
} from "./RemoteHostServer.js";

/** 信令侧依赖（由 SignalingClient 实现）。 */
export interface TunnelResponderSignaling {
  setInboundTunnelOpenHandler(handler: (event: { connectionId: number }) => void): void;
  clearInboundTunnelOpenHandler(): void;
  setTunnelHandler(
    connectionId: number,
    handler: (event: { type: string; connectionId: number; frame?: string; reason?: string }) => void
  ): void;
  removeTunnelHandler(connectionId: number): void;
  sendTunnelFrame(connectionId: number, seq: number, frame: string): boolean;
  sendTunnelClose(connectionId: number, reason: string): boolean;
}

/** 同网升级用的 LAN endpoint（每次调用应登记一个短期 token 后返回）。 */
export interface TunnelLanOffer {
  ip: string;
  port: number;
  token: string;
}

export interface RemoteTunnelResponderDeps {
  signaling: TunnelResponderSignaling;
  server: RemoteHostServer;
  /** 生成一份可用的 LAN offer（无可用 LAN 时返回 null）。 */
  lanOffer?: () => TunnelLanOffer | null;
}

const LAN_OFFER_RETRY_DELAYS_MS = [400, 900];

export class RemoteTunnelResponder {
  private readonly active = new Map<number, HostConnection>();
  /** 仍处于「开启」状态的 connectionId。先于 active 写入，使 attach 时回的 hello 能发出。 */
  private readonly openIds = new Set<number>();
  /** 全局出站帧序号（对应 Mac 的 nextSeq）。 */
  private nextSeq = 1;
  private attached = false;

  constructor(private readonly deps: RemoteTunnelResponderDeps) {}

  /** 开始监听入站隧道（host 激活时调用）。 */
  attach(): void {
    if (this.attached) return;
    this.attached = true;
    this.deps.signaling.setInboundTunnelOpenHandler((event) => this.open(event.connectionId));
  }

  /** 停止监听并关闭所有隧道（host 停用时调用）。 */
  detach(): void {
    if (!this.attached) return;
    this.attached = false;
    this.deps.signaling.clearInboundTunnelOpenHandler();
    for (const connectionId of [...this.active.keys()]) {
      this.close(connectionId, true, "host_stopped");
    }
  }

  get activeTunnelCount(): number {
    return this.active.size;
  }

  // MARK: - 隧道生命周期

  private open(connectionId: number): void {
    if (this.openIds.has(connectionId)) return;
    // 先标记为开启，确保 attachVirtualConnection 回的 hello 帧能通过 isOpen 校验发出。
    this.openIds.add(connectionId);

    const sink: HostConnectionSink = {
      send: (text) => this.sendFrame(connectionId, text),
      isOpen: () => this.openIds.has(connectionId),
      // 关闭由 responder 统一管理，避免 server.detach -> sink.close -> responder.close 循环。
      close: () => undefined
    };

    const connection = this.deps.server.attachVirtualConnection(sink);
    this.active.set(connectionId, connection);

    // 接管该 connectionId 的后续帧 / 关闭事件。
    this.deps.signaling.setTunnelHandler(connectionId, (event) => this.handleTunnelEvent(connectionId, event));

    // 同网手机：下发 LAN endpoint，自动升级为直连。
    this.sendLanOffer(connectionId);
  }

  private handleTunnelEvent(
    connectionId: number,
    event: { type: string; connectionId: number; frame?: string; reason?: string }
  ): void {
    switch (event.type) {
      case "tunnel_frame": {
        const frame = event.frame;
        if (typeof frame !== "string" || frame.length === 0) return;
        if (this.handleLanProbe(connectionId, frame)) return;
        const connection = this.active.get(connectionId);
        if (!connection) return;
        this.deps.server.deliverFrame(connection, frame);
        break;
      }
      case "tunnel_close":
      case "tunnel_error":
        this.close(connectionId, false, event.reason ?? "remote_closed");
        break;
      default:
        break;
    }
  }

  private close(connectionId: number, notifyRemote: boolean, reason: string): void {
    const connection = this.active.get(connectionId);
    this.openIds.delete(connectionId);
    if (!connection) return;
    this.active.delete(connectionId);
    this.deps.server.detachVirtualConnection(connection);
    this.deps.signaling.removeTunnelHandler(connectionId);
    if (notifyRemote) {
      this.deps.signaling.sendTunnelClose(connectionId, reason);
    }
  }

  // MARK: - 帧发送

  private sendFrame(connectionId: number, text: string): void {
    if (!this.openIds.has(connectionId)) return;
    const seq = this.nextSeq;
    this.nextSeq += 1;
    if (!this.deps.signaling.sendTunnelFrame(connectionId, seq, text)) {
      this.close(connectionId, false, "send_failed");
    }
  }

  // MARK: - LAN 升级

  /** 解析 `lan_request` 探测帧并回 `lan_offer`；命中返回 true（不再继续当作命令处理）。 */
  private handleLanProbe(connectionId: number, frame: string): boolean {
    let parsed: unknown;
    try {
      parsed = JSON.parse(frame);
    } catch {
      return false;
    }
    if (!parsed || typeof parsed !== "object") return false;
    if ((parsed as { type?: unknown }).type !== "lan_request") return false;
    this.sendLanOffer(connectionId);
    return true;
  }

  private sendLanOffer(connectionId: number): void {
    const offer = this.deps.lanOffer?.();
    if (!offer) return;
    const text = JSON.stringify({ type: "lan_offer", ip: offer.ip, port: offer.port, token: offer.token });
    this.sendFrame(connectionId, text);
    // 与 Mac 一致：补发两次，覆盖丢帧 / 时序窗口。
    for (const delay of LAN_OFFER_RETRY_DELAYS_MS) {
      setTimeout(() => {
        if (!this.active.has(connectionId)) return;
        // 复用最新 offer（token 可能已轮换）。
        const retryOffer = this.deps.lanOffer?.() ?? offer;
        const retryText = JSON.stringify({ type: "lan_offer", ip: retryOffer.ip, port: retryOffer.port, token: retryOffer.token });
        this.sendFrame(connectionId, retryText);
      }, delay);
    }
  }
}
