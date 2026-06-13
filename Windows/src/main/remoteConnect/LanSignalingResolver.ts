import type { SignalingClient } from "../signaling/SignalingClient.js";

export type LanDirectConfig = {
  host: string;
  port: number;
  token: string;
  transport: "lan";
};

export async function resolveLanViaSignaling(
  signalingClient: SignalingClient,
  connectionId: number,
  targetDeviceId: number,
  timeoutMs = 15_000
): Promise<LanDirectConfig | null> {
  if (signalingClient.status !== "connected") {
    return null;
  }

  return new Promise((resolve) => {
    let finished = false;
    const finish = (config: LanDirectConfig | null) => {
      if (finished) return;
      finished = true;
      clearTimeout(timer);
      signalingClient.removeTunnelHandler(connectionId);
      signalingClient.sendTunnelClose(connectionId, "lan_probe_done");
      resolve(config);
    };

    signalingClient.setTunnelHandler(connectionId, (event) => {
      switch (event.type) {
        case "tunnel_open_ack":
          signalingClient.sendTunnelFrame(connectionId, Date.now(), JSON.stringify({ type: "lan_request" }));
          break;
        case "tunnel_frame": {
          const config = parseLanOffer(event.frame);
          if (config) finish(config);
          break;
        }
        case "tunnel_close":
        case "tunnel_error":
          finish(null);
          break;
        default:
          break;
      }
    });

    if (!signalingClient.openTunnel(connectionId, targetDeviceId)) {
      finish(null);
      return;
    }
    signalingClient.sendTunnelFrame(connectionId, 1, JSON.stringify({ type: "lan_request" }));
    const timer = setTimeout(() => finish(null), timeoutMs);
  });
}

function parseLanOffer(frame?: string): LanDirectConfig | null {
  if (!frame) return null;
  try {
    const json = JSON.parse(frame) as { type?: string; ip?: string; port?: number; token?: string };
    if (json.type !== "lan_offer") return null;
    const ip = json.ip?.trim() ?? "";
    const port = json.port ?? 0;
    const token = json.token?.trim() ?? "";
    if (!ip || port < 1 || port > 65_535 || !token) return null;
    return { host: ip, port, token, transport: "lan" };
  } catch {
    return null;
  }
}
