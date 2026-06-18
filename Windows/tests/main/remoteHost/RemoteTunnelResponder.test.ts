import { describe, expect, it, vi } from "vitest";

import {
  RemoteHostServer,
  type RemoteHostServerDelegate
} from "../../../src/main/remoteHost/RemoteHostServer";
import {
  RemoteTunnelResponder,
  type TunnelLanOffer,
  type TunnelResponderSignaling
} from "../../../src/main/remoteHost/RemoteTunnelResponder";
import type { PanelStateEnvelope, ReplayPayload } from "../../../src/main/remoteHost/PanelStateBroadcaster";
import { makeCommand, makeResumeRequest, type PanelStateSnapshot } from "../../../src/shared/remoteProtocol";

type TunnelEvent = { type: string; connectionId: number; frame?: string; reason?: string };

class FakeSignaling implements TunnelResponderSignaling {
  inbound: ((event: { connectionId: number }) => void) | null = null;
  handlers = new Map<number, (event: TunnelEvent) => void>();
  sent: Array<{ connectionId: number; seq: number; frame: string }> = [];
  closed: Array<{ connectionId: number; reason: string }> = [];
  sendOk = true;

  setInboundTunnelOpenHandler(handler: (event: { connectionId: number }) => void): void {
    this.inbound = handler;
  }
  clearInboundTunnelOpenHandler(): void {
    this.inbound = null;
  }
  setTunnelHandler(connectionId: number, handler: (event: TunnelEvent) => void): void {
    this.handlers.set(connectionId, handler);
  }
  removeTunnelHandler(connectionId: number): void {
    this.handlers.delete(connectionId);
  }
  sendTunnelFrame(connectionId: number, seq: number, frame: string): boolean {
    this.sent.push({ connectionId, seq, frame });
    return this.sendOk;
  }
  sendTunnelClose(connectionId: number, reason: string): boolean {
    this.closed.push({ connectionId, reason });
    return true;
  }

  // test helpers
  fireOpen(connectionId: number): void {
    this.inbound?.({ connectionId });
  }
  fire(connectionId: number, event: TunnelEvent): void {
    this.handlers.get(connectionId)?.(event);
  }
  frameTypes(): string[] {
    return this.sent.map((entry) => JSON.parse(entry.frame).type as string);
  }
  reset(): void {
    this.sent = [];
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

function setup(lanOffer: TunnelLanOffer | null = { ip: "192.168.1.20", port: 18765, token: "lan-token" }) {
  const snapshot = buildSnapshot();
  const delegate = buildDelegate(snapshot);
  const server = new RemoteHostServer({ port: 0, token: "host-token", bindLAN: false }, delegate);
  const signaling = new FakeSignaling();
  const responder = new RemoteTunnelResponder({ signaling, server, lanOffer: () => lanOffer });
  responder.attach();
  return { snapshot, delegate, server, signaling, responder };
}

const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

describe("RemoteTunnelResponder", () => {
  it("attaches inbound handler and sends hello + lan_offer on tunnel_open", () => {
    const { signaling, responder } = setup();
    expect(signaling.inbound).toBeTypeOf("function");

    signaling.fireOpen(10);

    expect(responder.activeTunnelCount).toBe(1);
    expect(signaling.handlers.has(10)).toBe(true);
    expect(signaling.frameTypes()).toContain("hello");
    expect(signaling.frameTypes()).toContain("lan_offer");
  });

  it("feeds tunnel resume frames into the host pipeline and returns a panel_state frame", () => {
    const { signaling, delegate } = setup();
    signaling.fireOpen(10);
    signaling.reset();

    signaling.fire(10, {
      type: "tunnel_frame",
      connectionId: 10,
      frame: JSON.stringify(makeResumeRequest(null, null))
    });

    expect(delegate.replayPayload).toHaveBeenCalledTimes(1);
    expect(signaling.frameTypes()).toContain("panel_state");
  });

  it("answers lan_request probes with a lan_offer without touching the command pipeline", () => {
    const { signaling, delegate } = setup();
    signaling.fireOpen(10);
    signaling.reset();

    signaling.fire(10, {
      type: "tunnel_frame",
      connectionId: 10,
      frame: JSON.stringify({ type: "lan_request" })
    });

    expect(signaling.frameTypes()).toEqual(["lan_offer"]);
    expect(delegate.applyCommand).not.toHaveBeenCalled();
    expect(delegate.replayPayload).not.toHaveBeenCalled();
  });

  it("processes tunnel command frames and returns an ack", async () => {
    const { signaling, delegate } = setup();
    signaling.fireOpen(10);
    signaling.reset();

    signaling.fire(10, {
      type: "tunnel_frame",
      connectionId: 10,
      frame: JSON.stringify(makeCommand("requestSnapshot"))
    });
    await flush();

    expect(delegate.applyCommand).toHaveBeenCalledTimes(1);
    expect(signaling.frameTypes()).toContain("command_ack");
  });

  it("fans out broadcasts to the tunnel connection", () => {
    const { signaling, server, snapshot } = setup();
    signaling.fireOpen(10);
    signaling.reset();

    const envelope: PanelStateEnvelope = {
      type: "panel_state",
      kind: "snapshot",
      sessionId: null,
      revision: 1,
      snapshot
    };
    server.broadcast(envelope);

    expect(signaling.sent).toHaveLength(1);
    expect(JSON.parse(signaling.sent[0].frame).type).toBe("panel_state");
  });

  it("tears down the connection on tunnel_close and stops fanning out", () => {
    const { signaling, server, snapshot, responder } = setup();
    signaling.fireOpen(10);

    signaling.fire(10, { type: "tunnel_close", connectionId: 10, reason: "remote_closed" });

    expect(responder.activeTunnelCount).toBe(0);
    expect(signaling.handlers.has(10)).toBe(false);

    signaling.reset();
    server.broadcast({ type: "panel_state", kind: "snapshot", sessionId: null, revision: 1, snapshot });
    expect(signaling.sent).toHaveLength(0);
  });

  it("detach clears the inbound handler and closes active tunnels with notification", () => {
    const { signaling, responder } = setup();
    signaling.fireOpen(10);

    responder.detach();

    expect(signaling.inbound).toBeNull();
    expect(responder.activeTunnelCount).toBe(0);
    expect(signaling.handlers.has(10)).toBe(false);
    expect(signaling.closed).toEqual([{ connectionId: 10, reason: "host_stopped" }]);
  });
});
