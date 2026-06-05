import type { AccountSessionSummary } from "../../shared/account.js";
import { CredentialStore } from "../security/credentialStore.js";
import { remoteAuthSessionSchema, summarizeAccountSession, type RemoteAuthSession } from "./accountSchemas.js";

const sessionCredentialKey = "remote.account.session";

export class AccountSessionStore {
  constructor(private readonly credentials = new CredentialStore("account")) {}

  async loadSession(): Promise<RemoteAuthSession | null> {
    const raw = await this.credentials.readSecret(sessionCredentialKey);
    if (!raw) {
      return null;
    }
    return remoteAuthSessionSchema.parse(JSON.parse(raw));
  }

  async saveSession(session: RemoteAuthSession): Promise<AccountSessionSummary> {
    const parsed = remoteAuthSessionSchema.parse(session);
    await this.credentials.writeSecret(sessionCredentialKey, JSON.stringify(parsed));
    return summarizeAccountSession(parsed);
  }

  async clearSession(): Promise<void> {
    await this.credentials.deleteSecret(sessionCredentialKey);
  }

  async summary(): Promise<AccountSessionSummary> {
    return summarizeAccountSession(await this.loadSession());
  }

  async requireAccessToken(): Promise<string> {
    const session = await this.loadSession();
    if (!session) {
      throw new Error("Remote account session is missing.");
    }
    if (summarizeAccountSession(session).isExpired) {
      throw new Error("Remote account session is expired.");
    }
    return session.accessToken;
  }
}
