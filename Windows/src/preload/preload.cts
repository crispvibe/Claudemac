import { contextBridge, ipcRenderer } from "electron";
import type {
  AccountRemoteDeviceUpdateInput,
  AccountRemoteState,
  AccountRemoteBridge,
  AccountVerificationCodeResponse,
  AccountSessionSummary,
  DeviceCodeSummary,
  DeviceSummary,
  RemoteConnectResult,
  RemoteDevice,
  RemoteLegalDocument,
  RemoteLegalDocumentType
} from "../shared/account";
import type {
  AppInfo,
  AppUpdateCheckResponse,
  DesktopNotificationRequest,
  ProjectDirectorySelection,
  WindowControlAction
} from "../shared/ipc";
import type {
  AddProjectRequest,
  Project,
  ProjectListResponse,
  RemoveProjectRequest,
  SelectProjectRequest,
  TouchProjectRequest
} from "../shared/project";
import type { ScanFileTreeRequest, ScanFileTreeResponse } from "../shared/fileTree";
import type {
  EditorFileSelection,
  EditorFileStat,
  EditorOpenFileResult,
  EditorSaveFileResult
} from "../shared/editor";
import type {
  AppSettings,
  AppSettingsUpdate,
  CLIKind,
  CLIProbeResult,
  CLIProfile,
  CLIProfileCreateInput,
  CLIProfileUpdateInput
} from "../shared/settings";
import type {
  ChatBackendEventEnvelope,
  ChatInteractiveResponseRequest,
  ChatPermissionResponseRequest,
  ChatRunIDRequest,
  ChatSessionSnapshot,
  ChatStartRequest
} from "../shared/chat";

const ipcChannels = {
  appInfo: "app:info",
  appUpdateCheck: "app:update-check",
  selectProjectDirectory: "project:select-directory",
  windowControl: "window:control",
  projectList: "project:list",
  projectAdd: "project:add",
  projectRemove: "project:remove",
  projectTouch: "project:touch",
  projectSelect: "project:select",
  fileTreeScan: "file-tree:scan",
  editorSelectFile: "editor:select-file",
  editorOpenFile: "editor:open-file",
  editorSaveFile: "editor:save-file",
  editorStatFile: "editor:stat-file",
  settingsGet: "settings:get",
  settingsUpdate: "settings:update",
  settingsReset: "settings:reset",
  settingsProfileList: "settings:profile:list",
  settingsProfileCreate: "settings:profile:create",
  settingsProfileUpdate: "settings:profile:update",
  settingsProfileRemove: "settings:profile:remove",
  settingsProfileSetDefault: "settings:profile:set-default",
  settingsProfileSecretSet: "settings:profile:secret:set",
  settingsProfileSecretClear: "settings:profile:secret:clear",
  settingsCLIProbe: "settings:cli:probe",
  settingsAuthorizedFolderAdd: "settings:authorized-folder:add",
  settingsAuthorizedFolderRemove: "settings:authorized-folder:remove",
  accountRemoteGetState: "account-remote:get-state",
  accountRemoteRegisterCode: "account-remote:register-code",
  accountRemoteRegister: "account-remote:register",
  accountRemoteLogin: "account-remote:login",
  accountRemotePasswordResetCode: "account-remote:password-reset-code",
  accountRemotePasswordReset: "account-remote:password-reset",
  accountRemoteLogout: "account-remote:logout",
  accountRemoteChangePassword: "account-remote:change-password",
  accountRemoteDeleteAccount: "account-remote:delete-account",
  accountRemoteRefreshDevices: "account-remote:refresh-devices",
  accountRemoteRegisterDevice: "account-remote:register-device",
  accountRemoteUpdateDevice: "account-remote:update-device",
  accountRemoteRefreshDeviceCode: "account-remote:refresh-device-code",
  accountRemoteResetDeviceCode: "account-remote:reset-device-code",
  accountRemoteLegalDocument: "account-remote:legal-document",
  accountRemoteLegalConsent: "account-remote:legal-consent",
  accountRemoteStartSignaling: "account-remote:start-signaling",
  accountRemoteStopSignaling: "account-remote:stop-signaling",
  accountRemoteConnectDevice: "account-remote:connect-device",
  accountRemoteState: "account-remote:state",
  chatStart: "chat:start",
  chatInterrupt: "chat:interrupt",
  chatPermissionResponse: "chat:permission-response",
  chatInteractiveResponse: "chat:interactive-response",
  chatCompact: "chat:compact",
  chatSessionLoad: "chat-session:load",
  chatSessionSave: "chat-session:save",
  chatSessionDelete: "chat-session:delete",
  chatEvent: "chat:event",
  desktopNotificationShow: "desktop-notification:show"
} as const;

function toAppInfo(value: unknown): AppInfo {
  if (!value || typeof value !== "object") {
    throw new Error("Invalid app info response");
  }

  const info = value as Record<string, unknown>;
  if (typeof info.version !== "string" || typeof info.platform !== "string" || typeof info.arch !== "string") {
    throw new Error("Invalid app info response");
  }

  return {
    version: info.version,
    platform: info.platform,
    arch: info.arch
  };
}

function toProjectDirectorySelection(value: unknown): ProjectDirectorySelection {
  if (!value || typeof value !== "object") {
    throw new Error("Invalid project directory response");
  }

  const selection = value as Record<string, unknown>;
  if (typeof selection.canceled !== "boolean") {
    throw new Error("Invalid project directory response");
  }

  if (selection.path !== null && typeof selection.path !== "string") {
    throw new Error("Invalid project directory response");
  }

  return {
    canceled: selection.canceled,
    path: selection.path
  };
}

function toChatBackendEventEnvelope(value: unknown): ChatBackendEventEnvelope {
  if (!value || typeof value !== "object") {
    throw new Error("Invalid chat event envelope");
  }
  const envelope = value as Record<string, unknown>;
  if (typeof envelope.runID !== "string" || !envelope.event || typeof envelope.event !== "object") {
    throw new Error("Invalid chat event envelope");
  }
  return envelope as unknown as ChatBackendEventEnvelope;
}

function toAccountRemoteState(value: unknown): AccountRemoteState {
  if (!value || typeof value !== "object") {
    throw new Error("Invalid account remote state");
  }
  const state = value as {
    account?: AccountSessionSummary;
    device?: DeviceSummary | null;
    deviceCode?: DeviceCodeSummary;
    devices?: RemoteDevice[];
    signaling?: AccountRemoteState["signaling"];
  };
  if (!state.account || !state.signaling || !state.deviceCode || !Array.isArray(state.devices)) {
    throw new Error("Invalid account remote state");
  }
  return state as AccountRemoteState;
}

function toVerificationCodeResponse(value: unknown): AccountVerificationCodeResponse {
  if (!value || typeof value !== "object") {
    throw new Error("Invalid verification code response");
  }
  return value as AccountVerificationCodeResponse;
}

function toRemoteConnectResult(value: unknown): RemoteConnectResult {
  if (!value || typeof value !== "object") {
    throw new Error("Invalid remote connect result");
  }
  const result = value as Record<string, unknown>;
  if (typeof result.transport !== "string" || typeof result.token !== "string") {
    throw new Error("Invalid remote connect result");
  }
  return value as RemoteConnectResult;
}

function toRemoteLegalDocument(value: unknown): RemoteLegalDocument {
  if (!value || typeof value !== "object") {
    throw new Error("Invalid legal document response");
  }
  const document = value as Record<string, unknown>;
  if (
    typeof document.id !== "number"
    || typeof document.type !== "string"
    || typeof document.title !== "string"
    || typeof document.content !== "string"
  ) {
    throw new Error("Invalid legal document response");
  }
  return value as RemoteLegalDocument;
}

const chatEventListeners = new Set<(event: ChatBackendEventEnvelope) => void>();
const accountRemoteStateListeners = new Set<(state: AccountRemoteState) => void>();

ipcRenderer.on(ipcChannels.chatEvent, (_event, rawEnvelope: unknown) => {
  let envelope: ChatBackendEventEnvelope;
  try {
    envelope = toChatBackendEventEnvelope(rawEnvelope);
  } catch {
    return;
  }
  for (const listener of chatEventListeners) {
    listener(envelope);
  }
});

const api = {
  async getAppInfo(): Promise<AppInfo> {
    return toAppInfo(await ipcRenderer.invoke(ipcChannels.appInfo));
  },
  async checkAppUpdate(version: string): Promise<AppUpdateCheckResponse> {
    return ipcRenderer.invoke(ipcChannels.appUpdateCheck, { version }) as Promise<AppUpdateCheckResponse>;
  },
  async selectProjectDirectory(): Promise<ProjectDirectorySelection> {
    return toProjectDirectorySelection(await ipcRenderer.invoke(ipcChannels.selectProjectDirectory));
  },
  async windowControl(action: WindowControlAction): Promise<void> {
    await ipcRenderer.invoke(ipcChannels.windowControl, action);
  },
  async showDesktopNotification(request: DesktopNotificationRequest): Promise<boolean> {
    return ipcRenderer.invoke(ipcChannels.desktopNotificationShow, request) as Promise<boolean>;
  },
  projects: {
    async list(): Promise<ProjectListResponse> {
      return ipcRenderer.invoke(ipcChannels.projectList) as Promise<ProjectListResponse>;
    },
    async add(request: AddProjectRequest): Promise<Project> {
      return ipcRenderer.invoke(ipcChannels.projectAdd, request) as Promise<Project>;
    },
    async remove(request: RemoveProjectRequest): Promise<ProjectListResponse> {
      return ipcRenderer.invoke(ipcChannels.projectRemove, request) as Promise<ProjectListResponse>;
    },
    async touch(request: TouchProjectRequest): Promise<Project> {
      return ipcRenderer.invoke(ipcChannels.projectTouch, request) as Promise<Project>;
    },
    async select(request: SelectProjectRequest): Promise<ProjectListResponse> {
      return ipcRenderer.invoke(ipcChannels.projectSelect, request) as Promise<ProjectListResponse>;
    }
  },
  files: {
    async scan(request: ScanFileTreeRequest): Promise<ScanFileTreeResponse> {
      return ipcRenderer.invoke(ipcChannels.fileTreeScan, request) as Promise<ScanFileTreeResponse>;
    }
  },
  async selectEditorFile(): Promise<EditorFileSelection> {
    return ipcRenderer.invoke(ipcChannels.editorSelectFile) as Promise<EditorFileSelection>;
  },
  async openEditorFile(path: string): Promise<EditorOpenFileResult> {
    return ipcRenderer.invoke(ipcChannels.editorOpenFile, { path }) as Promise<EditorOpenFileResult>;
  },
  async saveEditorFile(path: string, text: string, expectedText: string): Promise<EditorSaveFileResult> {
    return ipcRenderer.invoke(ipcChannels.editorSaveFile, { path, text, expectedText }) as Promise<EditorSaveFileResult>;
  },
  async statEditorFile(path: string): Promise<EditorFileStat> {
    return ipcRenderer.invoke(ipcChannels.editorStatFile, { path }) as Promise<EditorFileStat>;
  },
  settings: {
    async get(): Promise<AppSettings> {
      return ipcRenderer.invoke(ipcChannels.settingsGet) as Promise<AppSettings>;
    },
    async update(patch: AppSettingsUpdate): Promise<AppSettings> {
      return ipcRenderer.invoke(ipcChannels.settingsUpdate, patch) as Promise<AppSettings>;
    },
    async reset(): Promise<AppSettings> {
      return ipcRenderer.invoke(ipcChannels.settingsReset) as Promise<AppSettings>;
    },
    profiles: {
      async list(kind?: CLIKind): Promise<CLIProfile[]> {
        return ipcRenderer.invoke(ipcChannels.settingsProfileList, kind) as Promise<CLIProfile[]>;
      },
      async create(input: CLIProfileCreateInput): Promise<CLIProfile> {
        return ipcRenderer.invoke(ipcChannels.settingsProfileCreate, input) as Promise<CLIProfile>;
      },
      async update(profileId: string, input: CLIProfileUpdateInput): Promise<CLIProfile> {
        return ipcRenderer.invoke(ipcChannels.settingsProfileUpdate, { profileId, input }) as Promise<CLIProfile>;
      },
      async remove(profileId: string): Promise<boolean> {
        return ipcRenderer.invoke(ipcChannels.settingsProfileRemove, { profileId }) as Promise<boolean>;
      },
      async setDefault(profileId: string): Promise<CLIProfile> {
        return ipcRenderer.invoke(ipcChannels.settingsProfileSetDefault, { profileId }) as Promise<CLIProfile>;
      },
      async setSecret(profileId: string, field: "apiKey" | "authToken", value: string): Promise<CLIProfile> {
        return ipcRenderer.invoke(ipcChannels.settingsProfileSecretSet, { profileId, field, value }) as Promise<CLIProfile>;
      },
      async clearSecret(profileId: string, field: "apiKey" | "authToken"): Promise<CLIProfile> {
        return ipcRenderer.invoke(ipcChannels.settingsProfileSecretClear, { profileId, field }) as Promise<CLIProfile>;
      }
    },
    async probe(kind: CLIKind, command?: string): Promise<CLIProbeResult> {
      return ipcRenderer.invoke(ipcChannels.settingsCLIProbe, { kind, command }) as Promise<CLIProbeResult>;
    },
    async addAuthorizedFolder(): Promise<AppSettings> {
      return ipcRenderer.invoke(ipcChannels.settingsAuthorizedFolderAdd) as Promise<AppSettings>;
    },
    async removeAuthorizedFolder(folderId: string): Promise<AppSettings> {
      return ipcRenderer.invoke(ipcChannels.settingsAuthorizedFolderRemove, { folderId }) as Promise<AppSettings>;
    }
  },
  accountRemote: {
    async getState(): Promise<AccountRemoteState> {
      return toAccountRemoteState(await ipcRenderer.invoke(ipcChannels.accountRemoteGetState));
    },
    async requestRegisterCode(email: string): Promise<AccountVerificationCodeResponse> {
      return toVerificationCodeResponse(await ipcRenderer.invoke(ipcChannels.accountRemoteRegisterCode, { email }));
    },
    async register(email: string, password: string, verificationCode: string): Promise<AccountRemoteState> {
      return toAccountRemoteState(await ipcRenderer.invoke(ipcChannels.accountRemoteRegister, { email, password, verificationCode }));
    },
    async login(email: string, password: string): Promise<AccountRemoteState> {
      return toAccountRemoteState(await ipcRenderer.invoke(ipcChannels.accountRemoteLogin, { email, password }));
    },
    async requestPasswordResetCode(email: string): Promise<AccountVerificationCodeResponse> {
      return toVerificationCodeResponse(await ipcRenderer.invoke(ipcChannels.accountRemotePasswordResetCode, { email }));
    },
    async resetPassword(email: string, password: string, verificationCode: string): Promise<boolean> {
      return ipcRenderer.invoke(ipcChannels.accountRemotePasswordReset, { email, password, verificationCode }) as Promise<boolean>;
    },
    async logout(): Promise<AccountRemoteState> {
      return toAccountRemoteState(await ipcRenderer.invoke(ipcChannels.accountRemoteLogout));
    },
    async changePassword(currentPassword: string, newPassword: string): Promise<AccountRemoteState> {
      return toAccountRemoteState(await ipcRenderer.invoke(ipcChannels.accountRemoteChangePassword, { currentPassword, newPassword }));
    },
    async deleteAccount(confirmAccount: string, confirmDestroy: string, confirmWaiveRights: string, reason: string): Promise<AccountRemoteState> {
      return toAccountRemoteState(await ipcRenderer.invoke(ipcChannels.accountRemoteDeleteAccount, {
        confirmAccount,
        confirmDestroy,
        confirmWaiveRights,
        reason
      }));
    },
    async refreshDevices(): Promise<AccountRemoteState> {
      return toAccountRemoteState(await ipcRenderer.invoke(ipcChannels.accountRemoteRefreshDevices));
    },
    async registerDevice(): Promise<AccountRemoteState> {
      return toAccountRemoteState(await ipcRenderer.invoke(ipcChannels.accountRemoteRegisterDevice));
    },
    async updateDevice(input: AccountRemoteDeviceUpdateInput): Promise<AccountRemoteState> {
      return toAccountRemoteState(await ipcRenderer.invoke(ipcChannels.accountRemoteUpdateDevice, input));
    },
    async refreshDeviceCode(): Promise<AccountRemoteState> {
      return toAccountRemoteState(await ipcRenderer.invoke(ipcChannels.accountRemoteRefreshDeviceCode));
    },
    async resetDeviceCode(): Promise<AccountRemoteState> {
      return toAccountRemoteState(await ipcRenderer.invoke(ipcChannels.accountRemoteResetDeviceCode));
    },
    async legalDocument(type: RemoteLegalDocumentType): Promise<RemoteLegalDocument> {
      return toRemoteLegalDocument(await ipcRenderer.invoke(ipcChannels.accountRemoteLegalDocument, { type }));
    },
    async consentLegal(documentId: number): Promise<boolean> {
      return ipcRenderer.invoke(ipcChannels.accountRemoteLegalConsent, { documentId }) as Promise<boolean>;
    },
    async startSignaling(): Promise<AccountRemoteState> {
      return toAccountRemoteState(await ipcRenderer.invoke(ipcChannels.accountRemoteStartSignaling));
    },
    async stopSignaling(): Promise<AccountRemoteState> {
      return toAccountRemoteState(await ipcRenderer.invoke(ipcChannels.accountRemoteStopSignaling));
    },
    async connectDevice(deviceId: number): Promise<RemoteConnectResult> {
      return toRemoteConnectResult(await ipcRenderer.invoke(ipcChannels.accountRemoteConnectDevice, { deviceId }));
    },
    onState(listener: (state: AccountRemoteState) => void): () => void {
      accountRemoteStateListeners.add(listener);
      return () => {
        accountRemoteStateListeners.delete(listener);
      };
    }
  } satisfies AccountRemoteBridge,
  chat: {
    async start(request: ChatStartRequest): Promise<{ runID: string }> {
      return ipcRenderer.invoke(ipcChannels.chatStart, request) as Promise<{ runID: string }>;
    },
    async interrupt(request: ChatRunIDRequest): Promise<boolean> {
      return ipcRenderer.invoke(ipcChannels.chatInterrupt, request) as Promise<boolean>;
    },
    async respondToPermission(request: ChatPermissionResponseRequest): Promise<boolean> {
      return ipcRenderer.invoke(ipcChannels.chatPermissionResponse, request) as Promise<boolean>;
    },
    async respondToInteractiveRequest(request: ChatInteractiveResponseRequest): Promise<boolean> {
      return ipcRenderer.invoke(ipcChannels.chatInteractiveResponse, request) as Promise<boolean>;
    },
    async sendCompact(request: ChatRunIDRequest): Promise<boolean> {
      return ipcRenderer.invoke(ipcChannels.chatCompact, request) as Promise<boolean>;
    },
    async loadSessions(): Promise<ChatSessionSnapshot> {
      return ipcRenderer.invoke(ipcChannels.chatSessionLoad) as Promise<ChatSessionSnapshot>;
    },
    async saveSessions(snapshot: ChatSessionSnapshot): Promise<boolean> {
      return ipcRenderer.invoke(ipcChannels.chatSessionSave, snapshot) as Promise<boolean>;
    },
    async deleteSession(sessionID: string): Promise<boolean> {
      return ipcRenderer.invoke(ipcChannels.chatSessionDelete, { sessionID }) as Promise<boolean>;
    },
    onEvent(listener: (event: ChatBackendEventEnvelope) => void): () => void {
      chatEventListeners.add(listener);
      return () => {
        chatEventListeners.delete(listener);
      };
    }
  }
};

ipcRenderer.on(ipcChannels.accountRemoteState, (_event, rawState: unknown) => {
  let state: AccountRemoteState;
  try {
    state = toAccountRemoteState(rawState);
  } catch {
    return;
  }
  for (const listener of accountRemoteStateListeners) {
    listener(state);
  }
});

contextBridge.exposeInMainWorld("acode", api);
