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
  lastError: null
};

describe("AccountRemotePanel", () => {
  it("shows online remote devices as unavailable until the connect bridge exists", () => {
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
              platform: "windows",
              deviceName: "Office PC",
              devicePublicKey: "public-key",
              deviceCodeHint: null,
              approvalPolicy: "always_ask",
              remoteEnabled: true,
              status: "active",
              appVersion: "0.1.0",
              online: true,
              lastSeenAt: "2026-05-28T00:00:00.000Z",
              lanEndpoint: null,
              transientToken: null
            }
          ]
        }}
      />
    );

    expect(screen.getByText("Office PC")).toBeInTheDocument();
    expect(screen.getByText("连接未接入")).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: /Office PC/u })).not.toBeInTheDocument();
  });
});
