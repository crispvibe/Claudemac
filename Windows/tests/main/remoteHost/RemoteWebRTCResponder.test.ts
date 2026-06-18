import { describe, expect, it, vi } from "vitest";

import {
  RemoteHostServer,
  type RemoteHostServerDelegate
} from "../../../src/main/remoteHost/RemoteHostServer";
import {
  RemoteWebRTCResponder,
  type WebRTCDataChannelLike,
  type WebRTCPeerLike,
  type WebRTCResponderSignaling
} from "../../../src/main/remoteHost/RemoteWebRTCResponder";
import type { PanelStateEnvelope, ReplayPayload } from "../../../src/main/remoteHost/PanelStateBroadcaster";
import type { InboundRelayEvent, SignalingPayload } from "../../../src/main/signaling/SignalingClient";
import { makeResumeRequest, type PanelStateSnapshot } from "../../../src/shared/remoteProtocol";

class FakeChannel implements WebRTCDataChannelLike {
  readyState = "connecting";
  sent: string[] = [];
  private msgCb?: (text: string) => void;
  private stateCb?: (state: string) => void;

  send(text: string): void {
    this.sent.push(text);
  }
  close(): void {
    this.readyState = "closed";
    this.stateCb?.("closed");
  }
  onMessage(listener: (text: string) => void): void {
    this.msgCb = listener;
  }
  onStateChange(listener: (state: string) => void): void {
    this.stateCb = listener;
  }
  open(): void {
    this.readyState = "open";
    this.stateCb?.("open");
  }
  emitMessage(text: string): void {
    this.msgCb?.(text);
  }
  frameTypes(): string[] {
    return this.sent.map((entry) => JSON.parse(entry).type as string);
  }
}

class FakePeer implements WebRTCPeerLike {
  remoteDesc: { type: string; sdp: string } | null = null;
  localDesc: { type: string; sdp: string } | null = null;
  addedCandidates: Array<{ candidate: string }> = [];
  closed = false;
  private iceCb?: (candidate: { candidate: string; sdpMid?: string; sdpMLineIndex?: number } | null) => void;
  private dcCb?: (channel: WebRTCDataChannelLike) => void;
  private csCb?: (state: string) => void;

  async setRemoteDescription(description: { type: string; sdp: string }): Promise<void> {
    this.remoteDesc = description;
  }
  async createAnswer(): Promise<{ type: string; sdp: string }> {
    return { type: "answer", sdp: "answer-sdp" };
  }
  async setLocalDescription(description: { type: string; sdp: string }): Promise<void> {
    this.localDesc = description;
  }
  localDescription(): { type: string; sdp: string } | null {
    return this.localDesc;
  }
  async addIceCandidate(candidate: { candidate: string }): Promise<void> {
    this.addedCandidates.push(candidate);
  }
  onIceCandidate(listener: (candidate: { candidate: string } | null) => void): void {
    this.iceCb = listener;
  }
  onDataChannel(listener: (channel: WebRTCDataChannelLike) => void): void {
    this.dcCb = listener;
  }
  onConnectionStateChange(listener: (state: string) => void): void {
    this.csCb = listener;
  }
  close(): void {
    this.closed = true;
  }
  emitIce(candidate: { candidate: string; sdpMid?: string; sdpMLineIndex?: number } | null): void {
    this.iceCb?.(candidate);
  }
  emitDataChannel(channel: WebRTCDataChannelLike): void {
    this.dcCb?.(channel);
  }
  emitConnectionState(state: string): void {
    this.csCb?.(state);
  }
}

class FakeSignaling implements WebRTCResponderSignaling {
  inbound: ((event: InboundRelayEvent) => void) | null = null;
  relays: Array<{ connectionId: number; toDeviceId: number; payload: SignalingPayload }> = [];

  setInboundRelayHandler(handler: (event: InboundRelayEvent) => void): void {
    this.inbound = handler;
  }
  clearInboundRelayHandler(): void {
    this.inbound = null;
  }
  relay(connectionId: number, toDeviceId: number, payload: SignalingPayload): boolean {
    this.relays.push({ connectionId, toDeviceId, payload });
    return true;
  }
  fire(event: InboundRelayEvent): void {
    this.inbound?.(event);
  }
  relayKinds(): string[] {
    return this.relays.map((entry) => entry.payload.type as string);
  }
}

function buildSnapshot(): PanelStateSnapshot {
  return { revision: 1, sessionId: null } as unknown as PanelStateSnapshot;
}

function buildDelegate(snapshot: PanelStateSnapshot): RemoteHostServerDelegate {
  return {
    applyCommand: vi.fn(async (command) => ({
      ack: { type: "command_ack", commandId: command.commandId, status: "ok", message: null, sessionId: null } as const,
      shouldUpdateFocusedSessionId: false,
      newFocusedSessionId: null,
      shouldPushSnapshotForFocus: false
    })),
    replayPayload: vi.fn((): ReplayPayload => ({ kind: "snapshot", snapshot })),
    snapshotFor: vi.fn(() => snapshot)
  };
}

function setup() {
  const snapshot = buildSnapshot();
  const delegate = buildDelegate(snapshot);
  const server = new RemoteHostServer({ port: 0, token: "host-token", bindLAN: false }, delegate);
  const signaling = new FakeSignaling();
  const peers: FakePeer[] = [];
  const responder = new RemoteWebRTCResponder({
    signaling,
    server,
    iceServers: async () => [],
    createPeer: async () => {
      const peer = new FakePeer();
      peers.push(peer);
      return peer;
    }
  });
  responder.attach();
  return { snapshot, delegate, server, signaling, responder, peers };
}

const flush = async (rounds = 6) => {
  for (let i = 0; i < rounds; i += 1) {
    await Promise.resolve();
    await new Promise((resolve) => setTimeout(resolve, 0));
  }
};

function relayEvent(overrides: Partial<InboundRelayEvent> & { payload: SignalingPayload }): InboundRelayEvent {
  return { connectionId: 7, fromDeviceId: 3, status: "accepted", ...overrides };
}

describe("RemoteWebRTCResponder", () => {
  it("answers an inbound offer relay and relays the answer SDP", async () => {
    const { signaling, peers } = setup();

    signaling.fire(relayEvent({ payload: { type: "offer", sdp: "offer-sdp" } as SignalingPayload }));
    await flush();

    expect(peers).toHaveLength(1);
    expect(peers[0].remoteDesc).toEqual({ type: "offer", sdp: "offer-sdp" });
    const answer = signaling.relays.find((entry) => entry.payload.type === "answer");
    expect(answer?.payload.sdp).toBe("answer-sdp");
    expect(answer?.toDeviceId).toBe(3);
  });

  it("adds remote candidates that arrive with/after the offer", async () => {
    const { signaling, peers } = setup();

    // 正确时序：offer 先到（开连接），candidate 紧随；二者在 peer 就绪前入队，按序处理后落到 peer。
    signaling.fire(relayEvent({ payload: { type: "offer", sdp: "offer-sdp" } as SignalingPayload }));
    signaling.fire(relayEvent({ payload: { type: "candidate", candidate: "cand-1", sdpMid: "0", sdpMLineIndex: 0 } as SignalingPayload }));
    await flush();

    expect(peers[0].addedCandidates.map((entry) => entry.candidate)).toContain("cand-1");
  });

  it("drops candidate relays that arrive before any offer (no idle bridge)", async () => {
    const { signaling, responder, peers } = setup();

    signaling.fire(relayEvent({ payload: { type: "candidate", candidate: "stray", sdpMid: "0", sdpMLineIndex: 0 } as SignalingPayload }));
    await flush();

    expect(responder.activePeerCount).toBe(0);
    expect(peers).toHaveLength(0);
  });

  it("relays locally generated ICE candidates", async () => {
    const { signaling, peers } = setup();
    signaling.fire(relayEvent({ payload: { type: "offer", sdp: "offer-sdp" } as SignalingPayload }));
    await flush();

    peers[0].emitIce({ candidate: "local-cand", sdpMid: "0", sdpMLineIndex: 0 });

    const candidate = signaling.relays.find((entry) => entry.payload.type === "candidate");
    expect(candidate?.payload.candidate).toBe("local-cand");
  });

  it("bridges the data channel into the host pipeline (hello + resume → panel_state)", async () => {
    const { signaling, peers, delegate } = setup();
    signaling.fire(relayEvent({ payload: { type: "offer", sdp: "offer-sdp" } as SignalingPayload }));
    await flush();

    const channel = new FakeChannel();
    peers[0].emitDataChannel(channel);
    channel.open();
    expect(channel.frameTypes()).toContain("hello");

    channel.emitMessage(JSON.stringify(makeResumeRequest(null, null)));
    expect(delegate.replayPayload).toHaveBeenCalledTimes(1);
    expect(channel.frameTypes()).toContain("panel_state");
  });

  it("fans out broadcasts to the webrtc connection", async () => {
    const { signaling, peers, server, snapshot } = setup();
    signaling.fire(relayEvent({ payload: { type: "offer", sdp: "offer-sdp" } as SignalingPayload }));
    await flush();

    const channel = new FakeChannel();
    peers[0].emitDataChannel(channel);
    channel.open();
    const before = channel.sent.length;

    server.broadcast({ type: "panel_state", kind: "snapshot", sessionId: null, revision: 1, snapshot } satisfies PanelStateEnvelope);

    expect(channel.sent.length).toBe(before + 1);
    expect(JSON.parse(channel.sent[channel.sent.length - 1]).type).toBe("panel_state");
  });

  it("closes the bridge and stops fanning out when the peer connection fails", async () => {
    const { signaling, peers, server, snapshot, responder } = setup();
    signaling.fire(relayEvent({ payload: { type: "offer", sdp: "offer-sdp" } as SignalingPayload }));
    await flush();

    const channel = new FakeChannel();
    peers[0].emitDataChannel(channel);
    channel.open();

    peers[0].emitConnectionState("failed");
    expect(responder.activePeerCount).toBe(0);
    expect(peers[0].closed).toBe(true);

    const before = channel.sent.length;
    server.broadcast({ type: "panel_state", kind: "snapshot", sessionId: null, revision: 1, snapshot });
    expect(channel.sent.length).toBe(before);
  });

  it("ignores relays whose connection is not accepted", async () => {
    const { signaling, responder, peers } = setup();

    signaling.fire(relayEvent({ status: "pending", payload: { type: "offer", sdp: "offer-sdp" } as SignalingPayload }));
    await flush();

    expect(responder.activePeerCount).toBe(0);
    expect(peers).toHaveLength(0);
  });

  it("detach clears the relay handler and closes active peers", async () => {
    const { signaling, responder, peers } = setup();
    signaling.fire(relayEvent({ payload: { type: "offer", sdp: "offer-sdp" } as SignalingPayload }));
    await flush();

    responder.detach();

    expect(signaling.inbound).toBeNull();
    expect(responder.activePeerCount).toBe(0);
    expect(peers[0].closed).toBe(true);
  });
});
