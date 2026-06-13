import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { AccountRemotePanel } from "../../../src/renderer/src/components/accountRemote/AccountRemotePanel";
import type { AccountRemoteViewState } from "../../../src/renderer/src/stores/accountStore";

const baseState: AccountRemoteViewState = {
  account: {
    status: "authenticated",
    userId: 1,
    displayAccount: "user@example.com",
    userStatus: "active",
    expiresAt: null,
    expiresAtISO: null,
    isExpired: false
  },
  device: {
    deviceUID: "11111111-1111-4111-8111-111111111111",
    deviceID: 10,
    deviceName: "Windows",
    devicePublicKey: "public-key",
    keyAlgorithm: "ed25519",
    hasDeviceCode: true
  },
  deviceCode: { deviceCode: null, hint: null },
  devices: [],
  connectionStatus: "connected",
  lastConnectedAt: null,
  lastError: null,
  activeConnection: null
};

describe("AccountRemotePanel", () => {
  it("shows connect action for active remote devices", () => {
    render(
      <AccountRemotePanel
        state={{
          ...baseState,
          devices: [
            {
              id: 11,
              userId: 1,
              deviceUid: "22222222-2222-4222-8222-222222222222",
              deviceType: "desktop",
              platform: "macos",
              deviceName: "Office Mac",
              devicePublicKey: "public-key",
              deviceCodeHint: null,
              approvalPolicy: "always_ask",
              remoteEnabled: true,
              status: "active",
              appVersion: "0.1.0",
              online: true,
              lastSeenAt: "2026-05-28T00:00:00.000Z",
              lanEndpoint: { ip: "192.168.2.196", port: 18765, lastSeenAt: "2026-05-28T00:00:00.000Z" },
              transientToken: "lan-token"
            }
          ]
        }}
      />
    );

    expect(screen.getByText("Office Mac")).toBeInTheDocument();
    expect(screen.getByText(/局域网可连接/u)).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "连接" })).toBeInTheDocument();
  });
});
