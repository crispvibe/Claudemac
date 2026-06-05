import { z } from "zod";
import {
  remoteAuthUserSchema,
  type AccountSessionSummary
} from "../../shared/account.js";

export const remoteAuthSessionSchema = z.object({
  accessToken: z.string().min(1),
  refreshToken: z.string().min(1),
  expiresAt: z.number().int(),
  user: remoteAuthUserSchema
});

export type RemoteAuthSession = z.output<typeof remoteAuthSessionSchema>;

export function summarizeAccountSession(session: RemoteAuthSession | null): AccountSessionSummary {
  if (!session) {
    return {
      status: "anonymous",
      userId: null,
      displayAccount: null,
      userStatus: null,
      expiresAt: null,
      expiresAtISO: null,
      isExpired: false
    };
  }

  const expiresAtDate = new Date(session.expiresAt);
  const isExpired = Number.isFinite(expiresAtDate.getTime()) && expiresAtDate <= new Date();
  const displayAccount = session.user.email || session.user.phone || `User ${session.user.id}`;

  return {
    status: isExpired ? "expired" : "authenticated",
    userId: session.user.id,
    displayAccount,
    userStatus: session.user.status,
    expiresAt: session.expiresAt,
    expiresAtISO: Number.isFinite(expiresAtDate.getTime()) ? expiresAtDate.toISOString() : null,
    isExpired
  };
}
