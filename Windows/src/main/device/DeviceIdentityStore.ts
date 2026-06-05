import { hostname } from "node:os";
import { createPrivateKey, generateKeyPairSync, randomUUID, sign } from "node:crypto";
import {
  localDeviceIdentitySchema,
  summarizeDeviceIdentity,
  type DeviceSummary,
  type LocalDeviceIdentity
} from "../../shared/account.js";
import { CredentialStore } from "../security/credentialStore.js";

const identityKey = "remote.device.identity";
const privateKeyKey = "remote.device.private-key";
const deviceCodeKey = "remote.device.code";

export class DeviceIdentityStore {
  constructor(private readonly credentials = new CredentialStore("device")) {}

  async loadIdentity(): Promise<LocalDeviceIdentity | null> {
    const raw = await this.credentials.readSecret(identityKey);
    if (!raw) {
      return null;
    }
    return localDeviceIdentitySchema.parse(JSON.parse(raw));
  }

  async loadOrCreateIdentity(deviceName = defaultDeviceName()): Promise<LocalDeviceIdentity> {
    const existing = await this.loadIdentity();
    if (existing) {
      return existing;
    }

    const keyPair = generateKeyPairSync("ed25519", {
      publicKeyEncoding: { type: "spki", format: "der" },
      privateKeyEncoding: { type: "pkcs8", format: "der" }
    });
    const identity = localDeviceIdentitySchema.parse({
      deviceUID: randomUUID(),
      deviceID: null,
      deviceName,
      devicePublicKey: keyPair.publicKey.toString("base64"),
      keyAlgorithm: "ed25519"
    });

    await this.credentials.writeSecret(privateKeyKey, keyPair.privateKey.toString("base64"));
    await this.saveIdentity(identity);
    return identity;
  }

  async saveIdentity(identity: LocalDeviceIdentity): Promise<void> {
    await this.credentials.writeSecret(identityKey, JSON.stringify(localDeviceIdentitySchema.parse(identity)));
  }

  async updateDeviceID(deviceID: number): Promise<DeviceSummary> {
    const identity = await this.loadOrCreateIdentity();
    const nextIdentity = localDeviceIdentitySchema.parse({ ...identity, deviceID });
    await this.saveIdentity(nextIdentity);
    return this.summary();
  }

  async updateDeviceName(deviceName: string): Promise<DeviceSummary> {
    const identity = await this.loadOrCreateIdentity();
    const nextIdentity = localDeviceIdentitySchema.parse({ ...identity, deviceName: deviceName.trim() || defaultDeviceName() });
    await this.saveIdentity(nextIdentity);
    return this.summary();
  }

  async saveDeviceCode(deviceCode: string): Promise<void> {
    const normalized = deviceCode.trim();
    if (!normalized) {
      await this.deleteDeviceCode();
      return;
    }
    await this.credentials.writeSecret(deviceCodeKey, normalized);
  }

  async loadDeviceCode(): Promise<string | null> {
    return this.credentials.readSecret(deviceCodeKey);
  }

  async deleteDeviceCode(): Promise<void> {
    await this.credentials.deleteSecret(deviceCodeKey);
  }

  async clearProvisionedDevice(): Promise<DeviceSummary> {
    const identity = await this.loadOrCreateIdentity();
    const nextIdentity = localDeviceIdentitySchema.parse({
      ...identity,
      deviceUID: randomUUID(),
      deviceID: null
    });
    await this.saveIdentity(nextIdentity);
    await this.deleteDeviceCode();
    return this.summary();
  }

  async signNonce(nonce: string): Promise<string> {
    const rawPrivateKey = await this.credentials.readSecret(privateKeyKey);
    if (!rawPrivateKey) {
      await this.loadOrCreateIdentity();
      return this.signNonce(nonce);
    }
    const privateKey = createPrivateKey({
      key: Buffer.from(rawPrivateKey, "base64"),
      format: "der",
      type: "pkcs8"
    });
    return sign(null, Buffer.from(nonce, "utf8"), privateKey).toString("base64");
  }

  async summary(): Promise<DeviceSummary> {
    const identity = await this.loadOrCreateIdentity();
    const hasDeviceCode = Boolean(await this.loadDeviceCode());
    return summarizeDeviceIdentity(identity, hasDeviceCode);
  }
}

function defaultDeviceName(): string {
  return hostname() || "Acode Windows";
}
