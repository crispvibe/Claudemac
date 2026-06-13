import { ipcMain } from "electron";
import {
  accountRemoteStateSchema,
  remoteConnectResultSchema,
  type AccountRemoteState,
  type DeviceCodeSummary,
  type RemoteDevice
} from "../../shared/account.js";
import {
  accountRemoteChangePasswordRequestSchema,
  accountRemoteConnectDeviceRequestSchema,
  accountRemoteDeleteAccountRequestSchema,
  accountRemoteDeviceUpdateRequestSchema,
  accountRemoteEmailRequestSchema,
  accountRemoteLegalConsentRequestSchema,
  accountRemoteLegalDocumentRequestSchema,
  accountRemoteLoginRequestSchema,
  accountRemotePasswordResetRequestSchema,
  accountRemoteRegisterRequestSchema,
  ipcChannels
} from "../../shared/ipc.js";
import type { RemoteAuthSession } from "./accountSchemas.js";
import { AccountClient } from "./AccountClient.js";
import { AccountSessionStore } from "./AccountSessionStore.js";
import { DeviceIdentityStore } from "../device/DeviceIdentityStore.js";
import { DeviceConnectService } from "../remoteConnect/DeviceConnectService.js";
import { SignalingClient } from "../signaling/SignalingClient.js";

export interface AccountRemoteIpcDependencies {
  accountClient: AccountClient;
  accountSessionStore: AccountSessionStore;
  deviceIdentityStore: DeviceIdentityStore;
  signalingClient: SignalingClient;
  publishState: (state: AccountRemoteState) => void;
}

export function registerAccountRemoteIpcHandlers({
  accountClient,
  accountSessionStore,
  deviceIdentityStore,
  signalingClient,
  publishState
}: AccountRemoteIpcDependencies): void {
  let cachedDevices: RemoteDevice[] = [];
  let cachedDeviceCode: DeviceCodeSummary = { deviceCode: null, hint: null };

  async function state(): Promise<AccountRemoteState> {
    const account = await accountSessionStore.summary();
    const device = await deviceIdentityStore.summary();
    return accountRemoteStateSchema.parse({
      account,
      device,
      deviceCode: cachedDeviceCode,
      devices: cachedDevices,
      signaling: signalingClient.summary()
    });
  }

  async function publishCurrentState(): Promise<AccountRemoteState> {
    const nextState = await state();
    publishState(nextState);
    return nextState;
  }

  async function refreshDevices(): Promise<RemoteDevice[]> {
    const accessToken = await accountSessionStore.requireAccessToken();
    cachedDevices = await accountClient.devices(accessToken);
    return cachedDevices;
  }

  async function refreshDeviceCode(accessToken: string, deviceID: number): Promise<DeviceCodeSummary> {
    const response = await accountClient.deviceCode(deviceID, accessToken);
    if (response.deviceCode) {
      await deviceIdentityStore.saveDeviceCode(response.deviceCode);
    }
    cachedDeviceCode = {
      deviceCode: response.deviceCode || await deviceIdentityStore.loadDeviceCode(),
      hint: response.hint
    };
    return cachedDeviceCode;
  }

  async function ensureSignalingStarted(accessToken?: string): Promise<void> {
    const token = accessToken ?? await accountSessionStore.requireAccessToken();
    let device = await deviceIdentityStore.summary();
    if (!device.deviceID) {
      return;
    }
    if (signalingClient.status === "connected" || signalingClient.status === "connecting" || signalingClient.status === "reconnecting") {
      return;
    }
    signalingClient.start(token, device.deviceID);
  }

  async function bootstrapAfterAuth(): Promise<void> {
    const accessToken = await accountSessionStore.requireAccessToken();
    await refreshDevices().catch(() => []);
    let identity = await deviceIdentityStore.syncDeviceNameWithHost();
    const remoteDevice = await accountClient.registerDevice({
      deviceUid: identity.deviceUID,
      deviceName: identity.deviceName,
      devicePublicKey: identity.devicePublicKey
    }, accessToken);
    await deviceIdentityStore.updateDeviceID(remoteDevice.id);
    if (remoteDevice.deviceName !== identity.deviceName) {
      await accountClient.updateDevice(remoteDevice.id, { deviceName: identity.deviceName }, accessToken).catch(() => undefined);
    }
    await refreshDeviceCode(accessToken, remoteDevice.id).catch(() => cachedDeviceCode);
    await refreshDevices().catch(() => []);
    await ensureSignalingStarted(accessToken).catch(() => undefined);
  }

  async function submitLegalConsents(session: RemoteAuthSession): Promise<void> {
    for (const type of ["user_agreement", "privacy_policy"] as const) {
      const document = await accountClient.legalDocument(type);
      await accountClient.consentLegal(document.id, session.accessToken);
    }
  }

  async function registerLocalDevice(): Promise<AccountRemoteState> {
    const accessToken = await accountSessionStore.requireAccessToken();
    const identity = await deviceIdentityStore.syncDeviceNameWithHost();
    const remoteDevice = await accountClient.registerDevice({
      deviceUid: identity.deviceUID,
      deviceName: identity.deviceName,
      devicePublicKey: identity.devicePublicKey
    }, accessToken);
    await deviceIdentityStore.updateDeviceID(remoteDevice.id);
    await refreshDeviceCode(accessToken, remoteDevice.id).catch(() => cachedDeviceCode);
    await refreshDevices();
    return publishCurrentState();
  }

  async function clearAccountAndDeviceState(resetProvisionedDevice: boolean): Promise<AccountRemoteState> {
    signalingClient.stop("account-cleared");
    await accountSessionStore.clearSession();
    cachedDevices = [];
    cachedDeviceCode = { deviceCode: null, hint: null };
    if (resetProvisionedDevice) {
      await deviceIdentityStore.clearProvisionedDevice().catch(() => undefined);
    } else {
      await deviceIdentityStore.deleteDeviceCode().catch(() => undefined);
    }
    return publishCurrentState();
  }

  signalingClient.on("status", () => {
    void publishCurrentState().catch((error: unknown) => {
      console.error("[account-remote] failed to publish signaling status", error);
    });
  });

  signalingClient.on("event", () => {
    void publishCurrentState().catch((error: unknown) => {
      console.error("[account-remote] failed to publish signaling event", error);
    });
  });

  ipcMain.handle(ipcChannels.accountRemoteGetState, async () => publishCurrentState());

  ipcMain.handle(ipcChannels.accountRemoteRegisterCode, async (_event, rawRequest: unknown) => {
    const request = accountRemoteEmailRequestSchema.parse(rawRequest);
    return accountClient.requestRegisterCode(request.email);
  });

  ipcMain.handle(ipcChannels.accountRemoteRegister, async (_event, rawRequest: unknown) => {
    const request = accountRemoteRegisterRequestSchema.parse(rawRequest);
    const session = await accountClient.register(request.email, request.password, request.verificationCode);
    await accountSessionStore.saveSession(session);
    await submitLegalConsents(session).catch((error: unknown) => {
      console.warn("[account-remote] failed to submit legal consent", error);
    });
    await bootstrapAfterAuth().catch(() => undefined);
    return publishCurrentState();
  });

  ipcMain.handle(ipcChannels.accountRemoteLogin, async (_event, rawRequest: unknown) => {
    const request = accountRemoteLoginRequestSchema.parse(rawRequest);
    const session = await accountClient.login(request.email, request.password);
    await accountSessionStore.saveSession(session);
    await submitLegalConsents(session).catch((error: unknown) => {
      console.warn("[account-remote] failed to submit legal consent", error);
    });
    await bootstrapAfterAuth().catch(() => undefined);
    return publishCurrentState();
  });

  ipcMain.handle(ipcChannels.accountRemotePasswordResetCode, async (_event, rawRequest: unknown) => {
    const request = accountRemoteEmailRequestSchema.parse(rawRequest);
    return accountClient.requestPasswordResetCode(request.email);
  });

  ipcMain.handle(ipcChannels.accountRemotePasswordReset, async (_event, rawRequest: unknown) => {
    const request = accountRemotePasswordResetRequestSchema.parse(rawRequest);
    await accountClient.resetPassword(request.email, request.password, request.verificationCode);
    return true;
  });

  ipcMain.handle(ipcChannels.accountRemoteLogout, async () => {
    signalingClient.stop("logout");
    const session = await accountSessionStore.loadSession();
    if (session) {
      const summary = await accountSessionStore.summary().catch(() => null);
      if (!summary?.isExpired) {
        await accountClient.logout(session.accessToken).catch(() => undefined);
      }
    }
    return clearAccountAndDeviceState(false);
  });

  ipcMain.handle(ipcChannels.accountRemoteChangePassword, async (_event, rawRequest: unknown) => {
    const request = accountRemoteChangePasswordRequestSchema.parse(rawRequest);
    await accountClient.changePassword(
      request.currentPassword,
      request.newPassword,
      await accountSessionStore.requireAccessToken()
    );
    return clearAccountAndDeviceState(false);
  });

  ipcMain.handle(ipcChannels.accountRemoteDeleteAccount, async (_event, rawRequest: unknown) => {
    const request = accountRemoteDeleteAccountRequestSchema.parse(rawRequest);
    await accountClient.deleteAccount(request, await accountSessionStore.requireAccessToken());
    return clearAccountAndDeviceState(true);
  });

  ipcMain.handle(ipcChannels.accountRemoteLegalDocument, async (_event, rawRequest: unknown) => {
    const request = accountRemoteLegalDocumentRequestSchema.parse(rawRequest);
    return accountClient.legalDocument(request.type);
  });

  ipcMain.handle(ipcChannels.accountRemoteLegalConsent, async (_event, rawRequest: unknown) => {
    const request = accountRemoteLegalConsentRequestSchema.parse(rawRequest);
    await accountClient.consentLegal(request.documentId, await accountSessionStore.requireAccessToken());
    return true;
  });

  ipcMain.handle(ipcChannels.accountRemoteRefreshDevices, async () => {
    await refreshDevices();
    return publishCurrentState();
  });

  ipcMain.handle(ipcChannels.accountRemoteRegisterDevice, async () => registerLocalDevice());

  ipcMain.handle(ipcChannels.accountRemoteUpdateDevice, async (_event, rawRequest: unknown) => {
    const request = accountRemoteDeviceUpdateRequestSchema.parse(rawRequest);
    const accessToken = await accountSessionStore.requireAccessToken();
    const device = await deviceIdentityStore.summary();
    if (!device.deviceID) {
      throw new Error("本机设备尚未注册，无法保存设备设置。");
    }
    const updated = await accountClient.updateDevice(device.deviceID, request, accessToken);
    if (request.deviceName) {
      await deviceIdentityStore.updateDeviceName(updated.deviceName);
    }
    await refreshDevices().catch(() => []);
    return publishCurrentState();
  });

  ipcMain.handle(ipcChannels.accountRemoteRefreshDeviceCode, async () => {
    const accessToken = await accountSessionStore.requireAccessToken();
    const device = await deviceIdentityStore.summary();
    if (!device.deviceID) {
      throw new Error("本机设备尚未注册，无法读取设备码。");
    }
    await refreshDeviceCode(accessToken, device.deviceID);
    return publishCurrentState();
  });

  ipcMain.handle(ipcChannels.accountRemoteResetDeviceCode, async () => {
    const accessToken = await accountSessionStore.requireAccessToken();
    const device = await deviceIdentityStore.summary();
    if (!device.deviceID) {
      throw new Error("本机设备尚未注册，无法重置设备码。");
    }
    const response = await accountClient.resetDeviceCode(device.deviceID, accessToken);
    if (response.deviceCode) {
      await deviceIdentityStore.saveDeviceCode(response.deviceCode);
    }
    cachedDeviceCode = response;
    return publishCurrentState();
  });

  ipcMain.handle(ipcChannels.accountRemoteStartSignaling, async () => {
    let device = await deviceIdentityStore.summary();
    if (!device.deviceID) {
      await registerLocalDevice();
      device = await deviceIdentityStore.summary();
    }
    if (!device.deviceID) {
      throw new Error("本机设备尚未注册，无法启动信令。");
    }
    signalingClient.start(await accountSessionStore.requireAccessToken(), device.deviceID);
    return publishCurrentState();
  });

  ipcMain.handle(ipcChannels.accountRemoteStopSignaling, async () => {
    signalingClient.stop("manual");
    return publishCurrentState();
  });

  const deviceConnectService = new DeviceConnectService(accountClient, deviceIdentityStore, signalingClient);

  void (async () => {
    try {
      const account = await accountSessionStore.summary();
      if (account.status !== "authenticated" || account.isExpired) {
        return;
      }
      const identity = await deviceIdentityStore.syncDeviceNameWithHost();
      const accessToken = await accountSessionStore.requireAccessToken();
      const device = await deviceIdentityStore.summary();
      if (device.deviceID && identity.deviceName !== device.deviceName) {
        await accountClient.updateDevice(device.deviceID, { deviceName: identity.deviceName }, accessToken).catch(() => undefined);
      }
      await refreshDevices().catch(() => []);
      await ensureSignalingStarted().catch(() => undefined);
      await publishCurrentState();
    } catch (error: unknown) {
      console.warn("[account-remote] failed to restore session", error);
    }
  })();

  ipcMain.handle(ipcChannels.accountRemoteConnectDevice, async (_event, rawRequest: unknown) => {
    const request = accountRemoteConnectDeviceRequestSchema.parse(rawRequest);
    const accessToken = await accountSessionStore.requireAccessToken();
    let device = await deviceIdentityStore.summary();
    if (!device.deviceID) {
      await registerLocalDevice();
      device = await deviceIdentityStore.summary();
    }
    if (!device.deviceID) {
      throw new Error("本机设备尚未注册，无法发起连接。");
    }
    if (signalingClient.status !== "connected") {
      signalingClient.start(accessToken, device.deviceID);
    }
    const result = await deviceConnectService.connectDevice(request.deviceId, accessToken);
    return remoteConnectResultSchema.parse(result);
  });
}
