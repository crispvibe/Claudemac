import { create } from "zustand";
import type { AccountRemoteState, AccountSessionSummary, DeviceCodeSummary, DeviceSummary, RemoteDevice } from "@shared/account";

export type AccountRemoteConnectionStatus = "idle" | "connecting" | "connected" | "reconnecting" | "closed" | "error";

export interface AccountRemoteViewState {
  account: AccountSessionSummary;
  device: DeviceSummary | null;
  deviceCode: DeviceCodeSummary;
  devices: RemoteDevice[];
  connectionStatus: AccountRemoteConnectionStatus;
  lastConnectedAt: string | null;
  lastError: string | null;
}

interface AccountRemoteStore extends AccountRemoteViewState {
  hydrate(summary: Partial<AccountRemoteViewState>): void;
  hydrateRemoteState(state: AccountRemoteState): void;
  setConnectionStatus(status: AccountRemoteConnectionStatus, error?: string | null): void;
  clearSensitiveViewState(): void;
}

const anonymousAccount: AccountSessionSummary = {
  status: "anonymous",
  userId: null,
  displayAccount: null,
  userStatus: null,
  expiresAt: null,
  expiresAtISO: null,
  isExpired: false
};

export const useAccountRemoteStore = create<AccountRemoteStore>((set) => ({
  account: anonymousAccount,
  device: null,
  deviceCode: { deviceCode: null, hint: null },
  devices: [],
  connectionStatus: "idle",
  lastConnectedAt: null,
  lastError: null,

  hydrate(summary) {
    set((state) => ({
      ...state,
      ...summary,
      account: summary.account ?? state.account,
      device: summary.device === undefined ? state.device : summary.device,
      deviceCode: summary.deviceCode ?? state.deviceCode,
      devices: summary.devices ?? state.devices
    }));
  },

  hydrateRemoteState(state) {
    set({
      account: state.account,
      device: state.device,
      deviceCode: state.deviceCode,
      devices: state.devices,
      connectionStatus: state.signaling.status,
      lastConnectedAt: state.signaling.lastConnectedAt,
      lastError: state.signaling.lastError
    });
  },

  setConnectionStatus(status, error = null) {
    set({
      connectionStatus: status,
      lastConnectedAt: status === "connected" ? new Date().toISOString() : null,
      lastError: error
    });
  },

  clearSensitiveViewState() {
    set({
      account: anonymousAccount,
      device: null,
      deviceCode: { deviceCode: null, hint: null },
      devices: [],
      connectionStatus: "idle",
      lastConnectedAt: null,
      lastError: null
    });
  }
}));
