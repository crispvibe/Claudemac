import { z } from "zod";

const fallbackStringSchema = (fallback: string) => z.string().optional().transform((value) => value ?? fallback);

const fallbackBooleanSchema = (fallback: boolean) => z.boolean().optional().transform((value) => value ?? fallback);

export const remoteAccountStatusSchema = z.enum(["anonymous", "authenticated", "expired", "error"]);
export type RemoteAccountStatus = z.infer<typeof remoteAccountStatusSchema>;

export const remoteAuthUserSchema = z.object({
  id: z.number().int().positive(),
  email: fallbackStringSchema(""),
  phone: z.string().nullable().optional(),
  status: fallbackStringSchema("active")
});

export type RemoteAuthUser = z.infer<typeof remoteAuthUserSchema>;

export const accountSessionSummarySchema = z.object({
  status: remoteAccountStatusSchema,
  userId: z.number().int().positive().nullable(),
  displayAccount: z.string().nullable(),
  userStatus: z.string().nullable(),
  expiresAt: z.number().int().nullable(),
  expiresAtISO: z.string().nullable(),
  isExpired: z.boolean()
});

export type AccountSessionSummary = z.infer<typeof accountSessionSummarySchema>;

export const localDeviceIdentitySchema = z.object({
  deviceUID: z.string().uuid(),
  deviceID: z.number().int().positive().nullable(),
  deviceName: z.string().min(1),
  devicePublicKey: z.string().min(1),
  keyAlgorithm: z.enum(["ed25519"]).default("ed25519")
});

export type LocalDeviceIdentity = z.infer<typeof localDeviceIdentitySchema>;

export const deviceSummarySchema = z.object({
  deviceUID: z.string().uuid(),
  deviceID: z.number().int().positive().nullable(),
  deviceName: z.string(),
  devicePublicKey: z.string(),
  keyAlgorithm: z.enum(["ed25519"]),
  hasDeviceCode: z.boolean()
});

export type DeviceSummary = z.infer<typeof deviceSummarySchema>;

export const deviceCodeSummarySchema = z.object({
  deviceCode: z.string().nullable().optional().transform((value) => value ?? null),
  hint: z.string().nullable().optional().transform((value) => value ?? null)
});

export type DeviceCodeSummary = z.infer<typeof deviceCodeSummarySchema>;

export const remoteLanEndpointSchema = z.object({
  ip: z.string(),
  port: z.number().int().min(1).max(65535),
  lastSeenAt: z.string().nullable().optional()
});

export type RemoteLanEndpoint = z.infer<typeof remoteLanEndpointSchema>;

export const remoteDeviceSchema = z.object({
  id: z.number().int().positive(),
  userId: z.number().int().positive().nullable().optional(),
  deviceUid: z.string().nullable().optional(),
  deviceType: z.string().nullable().optional(),
  platform: z.string().nullable().optional(),
  deviceName: z.string(),
  devicePublicKey: z.string().nullable().optional(),
  deviceCodeHint: z.string().nullable().optional(),
  approvalPolicy: fallbackStringSchema("always_ask"),
  remoteEnabled: fallbackBooleanSchema(true),
  status: fallbackStringSchema("active"),
  appVersion: z.string().nullable().optional(),
  online: fallbackBooleanSchema(false),
  lastSeenAt: z.string().nullable().optional(),
  lanEndpoint: remoteLanEndpointSchema.nullable().optional(),
  lan_endpoint: remoteLanEndpointSchema.nullable().optional(),
  transientToken: z.string().nullable().optional(),
  transient_token: z.string().nullable().optional()
}).transform(({ lan_endpoint, transient_token, lanEndpoint, transientToken, ...rest }) => ({
  ...rest,
  lanEndpoint: lanEndpoint ?? lan_endpoint ?? null,
  transientToken: transientToken ?? transient_token ?? null
}));

export type RemoteDevice = z.infer<typeof remoteDeviceSchema>;

export const remoteConnectionAttemptSchema = z.object({
  id: z.number().int().positive(),
  connectionId: z.number().int().positive().nullable().optional(),
  fromUserId: z.number().int().positive().nullable().optional(),
  fromDeviceId: z.number().int().positive().nullable().optional(),
  toUserId: z.number().int().positive().nullable().optional(),
  toDeviceId: z.number().int().positive().nullable().optional(),
  status: z.string(),
  reason: z.string().nullable().optional(),
  transport: z.string().nullable().optional(),
  endpoint: remoteLanEndpointSchema.nullable().optional(),
  transientToken: z.string().nullable().optional(),
  transient_token: z.string().nullable().optional()
}).transform(({ transient_token, transientToken, ...rest }) => ({
  ...rest,
  transientToken: transientToken ?? transient_token ?? null
}));

export type RemoteConnectionAttempt = z.infer<typeof remoteConnectionAttemptSchema>;

export const remoteConnectResultSchema = z.object({
  transport: z.enum(["lan", "tunnel", "public"]),
  host: z.string().default(""),
  port: z.number().int().default(0),
  token: z.string(),
  connectionId: z.number().int().positive().nullable().optional(),
  targetDeviceId: z.number().int().positive().nullable().optional(),
  message: z.string().nullable().optional()
});

export type RemoteConnectResult = z.infer<typeof remoteConnectResultSchema>;

export const accountRemoteStateSchema = z.object({
  account: accountSessionSummarySchema,
  device: deviceSummarySchema.nullable(),
  deviceCode: deviceCodeSummarySchema,
  devices: z.array(remoteDeviceSchema),
  signaling: z.object({
    status: z.enum(["idle", "connecting", "connected", "reconnecting", "closed", "error"]),
    lastConnectedAt: z.string().nullable(),
    lastError: z.string().nullable()
  })
});

export type AccountRemoteState = z.infer<typeof accountRemoteStateSchema>;

export const accountVerificationCodeResponseSchema = z.object({
  verificationCode: z.string().optional().default(""),
  expiresAt: z.number().int().nullable().optional().default(null)
});

export type AccountVerificationCodeResponse = z.infer<typeof accountVerificationCodeResponseSchema>;

export const remoteLegalDocumentTypeSchema = z.enum(["privacy_policy", "user_agreement"]);
export type RemoteLegalDocumentType = z.infer<typeof remoteLegalDocumentTypeSchema>;

export const remoteLegalDocumentSchema = z.object({
  id: z.number().int().positive(),
  type: remoteLegalDocumentTypeSchema,
  platform: fallbackStringSchema(""),
  version: fallbackStringSchema(""),
  title: fallbackStringSchema(""),
  contentFormat: fallbackStringSchema("plain_text"),
  content: fallbackStringSchema(""),
  published: fallbackBooleanSchema(false)
});

export type RemoteLegalDocument = z.infer<typeof remoteLegalDocumentSchema>;

export const accountRemoteDeviceUpdateInputSchema = z.object({
  deviceName: z.string().min(1).optional(),
  approvalPolicy: z.enum(["always_ask", "allow_anyone"]).optional(),
  remoteEnabled: z.boolean().optional()
});

export type AccountRemoteDeviceUpdateInput = z.infer<typeof accountRemoteDeviceUpdateInputSchema>;

export interface AccountRemoteBridge {
  getState: () => Promise<AccountRemoteState>;
  requestRegisterCode: (email: string) => Promise<AccountVerificationCodeResponse>;
  register: (email: string, password: string, verificationCode: string) => Promise<AccountRemoteState>;
  login: (email: string, password: string) => Promise<AccountRemoteState>;
  requestPasswordResetCode: (email: string) => Promise<AccountVerificationCodeResponse>;
  resetPassword: (email: string, password: string, verificationCode: string) => Promise<boolean>;
  logout: () => Promise<AccountRemoteState>;
  changePassword: (currentPassword: string, newPassword: string) => Promise<AccountRemoteState>;
  deleteAccount: (confirmAccount: string, confirmDestroy: string, confirmWaiveRights: string, reason: string) => Promise<AccountRemoteState>;
  refreshDevices: () => Promise<AccountRemoteState>;
  registerDevice: () => Promise<AccountRemoteState>;
  updateDevice: (input: AccountRemoteDeviceUpdateInput) => Promise<AccountRemoteState>;
  refreshDeviceCode: () => Promise<AccountRemoteState>;
  resetDeviceCode: () => Promise<AccountRemoteState>;
  legalDocument: (type: RemoteLegalDocumentType) => Promise<RemoteLegalDocument>;
  consentLegal: (documentId: number) => Promise<boolean>;
  startSignaling: () => Promise<AccountRemoteState>;
  stopSignaling: () => Promise<AccountRemoteState>;
  connectDevice: (deviceId: number) => Promise<RemoteConnectResult>;
  onState: (listener: (state: AccountRemoteState) => void) => () => void;
}

export function summarizeDeviceIdentity(identity: LocalDeviceIdentity, hasDeviceCode: boolean): DeviceSummary {
  return {
    deviceUID: identity.deviceUID,
    deviceID: identity.deviceID,
    deviceName: identity.deviceName,
    devicePublicKey: identity.devicePublicKey,
    keyAlgorithm: identity.keyAlgorithm,
    hasDeviceCode
  };
}
