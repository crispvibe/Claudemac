import { z } from "zod";
import { accountRemoteDeviceUpdateInputSchema, remoteLegalDocumentTypeSchema } from "./account.js";
import { secretFieldSchema } from "./settings.js";

export const ipcChannels = {
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

export const appInfoSchema = z.object({
  version: z.string(),
  platform: z.string(),
  arch: z.string()
});

export type AppInfo = z.infer<typeof appInfoSchema>;

export const desktopNotificationRequestSchema = z.object({
  title: z.string().min(1).max(120),
  body: z.string().max(512).default("")
});

export type DesktopNotificationRequest = z.infer<typeof desktopNotificationRequestSchema>;

export const appUpdateCheckRequestSchema = z.object({
  version: z.string().default("0.0.0")
});

export const appUpdateCheckResponseSchema = z.object({
  updateAvailable: z.boolean().default(false),
  latestVersion: z.string().default(""),
  latestBuildNumber: z.string().default(""),
  releaseNotes: z.string().default(""),
  updateType: z.string().default("link"),
  downloadUrl: z.string().default(""),
  appStoreUrl: z.string().default(""),
  forceUpdate: z.boolean().default(false)
});

export type AppUpdateCheckRequest = z.infer<typeof appUpdateCheckRequestSchema>;
export type AppUpdateCheckResponse = z.infer<typeof appUpdateCheckResponseSchema>;

export const projectDirectorySchema = z.object({
  canceled: z.boolean(),
  path: z.string().nullable()
});

export type ProjectDirectorySelection = z.infer<typeof projectDirectorySchema>;

export const windowControlActionSchema = z.enum(["minimize", "toggleMaximize", "close"]);

export type WindowControlAction = z.infer<typeof windowControlActionSchema>;

export const settingsProfileUpdateRequestSchema = z.object({
  profileId: z.string().min(1),
  input: z.unknown()
});

export const settingsProfileIdRequestSchema = z.object({
  profileId: z.string().min(1)
});

export const settingsProfileSecretSetRequestSchema = z.object({
  profileId: z.string().min(1),
  field: secretFieldSchema,
  value: z.string()
});

export const settingsProfileSecretClearRequestSchema = z.object({
  profileId: z.string().min(1),
  field: secretFieldSchema
});

export const settingsCLIProbeRequestSchema = z.object({
  kind: z.enum(["claude", "codex"]),
  command: z.string().optional()
});

export const settingsAuthorizedFolderRemoveRequestSchema = z.object({
  folderId: z.string().min(1)
});

export const accountRemoteLoginRequestSchema = z.object({
  email: z.string().min(1),
  password: z.string().min(1)
});

export const accountRemoteEmailRequestSchema = z.object({
  email: z.string().min(1)
});

export const accountRemoteRegisterRequestSchema = z.object({
  email: z.string().min(1),
  password: z.string().min(1),
  verificationCode: z.string().min(1)
});

export const accountRemotePasswordResetRequestSchema = accountRemoteRegisterRequestSchema;

export const accountRemoteChangePasswordRequestSchema = z.object({
  currentPassword: z.string().min(1),
  newPassword: z.string().min(1)
});

export const accountRemoteDeleteAccountRequestSchema = z.object({
  confirmAccount: z.string().min(1),
  confirmDestroy: z.string().min(1),
  confirmWaiveRights: z.string().min(1),
  reason: z.string().default("")
});

export const accountRemoteLegalDocumentRequestSchema = z.object({
  type: remoteLegalDocumentTypeSchema
});

export const accountRemoteLegalConsentRequestSchema = z.object({
  documentId: z.number().int().positive()
});

export const accountRemoteDeviceUpdateRequestSchema = accountRemoteDeviceUpdateInputSchema;

export const accountRemoteConnectDeviceRequestSchema = z.object({
  deviceId: z.number().int().positive()
});

export type SettingsProfileUpdateRequest = z.infer<typeof settingsProfileUpdateRequestSchema>;
export type SettingsProfileIdRequest = z.infer<typeof settingsProfileIdRequestSchema>;
export type SettingsProfileSecretSetRequest = z.infer<typeof settingsProfileSecretSetRequestSchema>;
export type SettingsProfileSecretClearRequest = z.infer<typeof settingsProfileSecretClearRequestSchema>;
export type SettingsCLIProbeRequest = z.infer<typeof settingsCLIProbeRequestSchema>;
export type SettingsAuthorizedFolderRemoveRequest = z.infer<typeof settingsAuthorizedFolderRemoveRequestSchema>;
export type AccountRemoteLoginRequest = z.infer<typeof accountRemoteLoginRequestSchema>;
export type AccountRemoteEmailRequest = z.infer<typeof accountRemoteEmailRequestSchema>;
export type AccountRemoteRegisterRequest = z.infer<typeof accountRemoteRegisterRequestSchema>;
export type AccountRemotePasswordResetRequest = z.infer<typeof accountRemotePasswordResetRequestSchema>;
export type AccountRemoteChangePasswordRequest = z.infer<typeof accountRemoteChangePasswordRequestSchema>;
export type AccountRemoteDeleteAccountRequest = z.infer<typeof accountRemoteDeleteAccountRequestSchema>;
export type AccountRemoteLegalDocumentRequest = z.infer<typeof accountRemoteLegalDocumentRequestSchema>;
export type AccountRemoteLegalConsentRequest = z.infer<typeof accountRemoteLegalConsentRequestSchema>;
export type AccountRemoteDeviceUpdateRequest = z.infer<typeof accountRemoteDeviceUpdateRequestSchema>;
