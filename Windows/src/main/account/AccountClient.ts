import { z } from "zod";
import {
  accountVerificationCodeResponseSchema,
  deviceCodeSummarySchema,
  remoteDeviceSchema,
  remoteLegalDocumentSchema,
  type AccountRemoteDeviceUpdateInput,
  type AccountVerificationCodeResponse,
  type DeviceCodeSummary,
  type RemoteDevice,
  type RemoteLegalDocument,
  type RemoteLegalDocumentType
} from "../../shared/account.js";
import { remoteAuthSessionSchema, type RemoteAuthSession } from "./accountSchemas.js";

const apiEnvelopeSchema = <T extends z.ZodTypeAny>(payload: T) => z.object({
  code: z.number().int().default(-1),
  data: payload.nullable().optional(),
  msg: z.string().default("")
});

const emptyPayloadSchema = z.object({}).passthrough();

export const accountClientConfigSchema = z.object({
  baseURL: z.string().url().default("https://acode.anna.vin"),
  platform: z.literal("windows").default("windows"),
  appVersion: z.string().default("0.1.0")
});

export type AccountClientConfig = z.infer<typeof accountClientConfigSchema>;

export class AccountAPIError extends Error {
  readonly code: number;
  readonly status: number;

  constructor(message: string, code: number, status: number) {
    super(message);
    this.name = "AccountAPIError";
    this.code = code;
    this.status = status;
  }
}

export class AccountClient {
  private readonly config: AccountClientConfig;

  constructor(config: Partial<AccountClientConfig> = {}, private readonly fetchImpl: typeof fetch = fetch) {
    this.config = accountClientConfigSchema.parse(config);
  }

  login(email: string, password: string): Promise<RemoteAuthSession> {
    return this.post("remote/auth/login", remoteAuthSessionSchema, {
      ...accountIdentifierPayload(email),
      password
    });
  }

  requestRegisterCode(email: string): Promise<AccountVerificationCodeResponse> {
    return this.post("remote/auth/register-code", accountVerificationCodeResponseSchema, {
      ...accountIdentifierPayload(email)
    });
  }

  register(email: string, password: string, verificationCode: string): Promise<RemoteAuthSession> {
    return this.post("remote/auth/register", remoteAuthSessionSchema, {
      ...accountIdentifierPayload(email),
      password,
      verificationCode: verificationCode.trim()
    });
  }

  refresh(refreshToken: string): Promise<RemoteAuthSession> {
    return this.post("remote/auth/refresh", remoteAuthSessionSchema, { refreshToken });
  }

  async logout(accessToken: string): Promise<void> {
    await this.post("remote/auth/logout", emptyPayloadSchema, {}, accessToken);
  }

  requestPasswordResetCode(email: string): Promise<AccountVerificationCodeResponse> {
    return this.post("remote/auth/password-reset-code", accountVerificationCodeResponseSchema, {
      ...accountIdentifierPayload(email)
    });
  }

  async resetPassword(email: string, password: string, verificationCode: string): Promise<void> {
    await this.post("remote/auth/reset-password", emptyPayloadSchema, {
      ...accountIdentifierPayload(email),
      password,
      verificationCode: verificationCode.trim()
    });
  }

  async changePassword(currentPassword: string, newPassword: string, accessToken: string): Promise<void> {
    await this.post("remote/auth/change-password", emptyPayloadSchema, {
      currentPassword,
      newPassword
    }, accessToken);
  }

  async deleteAccount(input: {
    confirmAccount: string;
    confirmDestroy: string;
    confirmWaiveRights: string;
    reason: string;
  }, accessToken: string): Promise<void> {
    await this.post("remote/account/deletion", emptyPayloadSchema, input, accessToken);
  }

  legalDocument(type: RemoteLegalDocumentType): Promise<RemoteLegalDocument> {
    return this.fetchLegalDocument(type, this.config.platform).catch(() => this.fetchLegalDocument(type, "macos"));
  }

  private fetchLegalDocument(type: RemoteLegalDocumentType, platform: string): Promise<RemoteLegalDocument> {
    const query = new URLSearchParams({
      platform,
      type
    });
    return this.get(`remote/legal-documents?${query.toString()}`, remoteLegalDocumentSchema);
  }

  async consentLegal(documentId: number, accessToken: string, deviceId = 0): Promise<void> {
    await this.post("remote/legal-consents", emptyPayloadSchema, {
      deviceId,
      documentId,
      platform: this.config.platform
    }, accessToken);
  }

  devices(accessToken: string): Promise<RemoteDevice[]> {
    return this.get("remote/devices", z.array(remoteDeviceSchema), accessToken);
  }

  registerDevice(input: {
    deviceUid: string;
    deviceName: string;
    devicePublicKey: string;
  }, accessToken: string): Promise<RemoteDevice> {
    return this.post("remote/devices/register", remoteDeviceSchema, {
      deviceUid: input.deviceUid,
      deviceType: "desktop",
      platform: this.config.platform,
      deviceName: input.deviceName,
      devicePublicKey: input.devicePublicKey,
      appVersion: this.config.appVersion
    }, accessToken);
  }

  deviceCode(deviceId: number, accessToken: string): Promise<DeviceCodeSummary> {
    return this.get(`remote/devices/${deviceId}/device-code`, deviceCodeSummarySchema, accessToken);
  }

  resetDeviceCode(deviceId: number, accessToken: string): Promise<DeviceCodeSummary> {
    return this.post(`remote/devices/${deviceId}/device-code/reset`, deviceCodeSummarySchema, {}, accessToken);
  }

  updateDevice(deviceId: number, input: AccountRemoteDeviceUpdateInput, accessToken: string): Promise<RemoteDevice> {
    return this.patch(`remote/devices/${deviceId}`, remoteDeviceSchema, {
      ...input,
      appVersion: this.config.appVersion
    }, accessToken);
  }

  async get<TSchema extends z.ZodTypeAny>(path: string, schema: TSchema, accessToken?: string): Promise<z.output<TSchema>> {
    return this.perform(path, "GET", schema, undefined, accessToken);
  }

  async post<TSchema extends z.ZodTypeAny>(path: string, schema: TSchema, body: unknown, accessToken?: string): Promise<z.output<TSchema>> {
    return this.perform(path, "POST", schema, body, accessToken);
  }

  async patch<TSchema extends z.ZodTypeAny>(path: string, schema: TSchema, body: unknown, accessToken?: string): Promise<z.output<TSchema>> {
    return this.perform(path, "PATCH", schema, body, accessToken);
  }

  private async perform<TSchema extends z.ZodTypeAny>(
    apiPath: string,
    method: "GET" | "POST" | "PATCH",
    schema: TSchema,
    body?: unknown,
    accessToken?: string
  ): Promise<z.output<TSchema>> {
    const url = new URL(apiPath.startsWith("/") ? apiPath : `/${apiPath}`, this.config.baseURL);
    const headers = new Headers({ Accept: "application/json" });
    if (accessToken) {
      headers.set("Authorization", `Bearer ${accessToken}`);
    }
    if (body !== undefined) {
      headers.set("Content-Type", "application/json");
    }

    const response = await this.fetchImpl(url, {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body)
    });
    const text = await response.text();
    const raw = text ? JSON.parse(text) as unknown : {};
    const envelope = apiEnvelopeSchema(schema).parse(raw);
    if (!response.ok || envelope.code !== 0) {
      throw new AccountAPIError(envelope.msg || `Remote API request failed with HTTP ${response.status}.`, envelope.code, response.status);
    }
    if (envelope.data === null || envelope.data === undefined) {
      return schema.parse({});
    }
    return envelope.data;
  }
}

function normalizeAccount(value: string): string {
  return value.trim().toLowerCase();
}

function accountIdentifierPayload(value: string): { email?: string; phone?: string } {
  const account = normalizeAccount(value);
  if (account.includes("@")) {
    return { email: account };
  }
  return { phone: account.replace(/[\s-]/g, "") };
}
