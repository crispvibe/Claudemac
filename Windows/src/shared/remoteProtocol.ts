import { z } from "zod";

const uuidSchema = z.string().uuid();
const isoDateStringSchema = z.string().datetime({ offset: true });

export const remoteVNCFrameType = {
  command: "command",
  commandAck: "command_ack",
  panelState: "panel_state",
  resume: "resume"
} as const;

export const chatMessageAttachmentSchema = z.object({
  id: uuidSchema.optional(),
  filename: z.string(),
  path: z.string(),
  mimeType: z.string().optional(),
  byteSize: z.number().int().nonnegative().optional(),
  thumbnailData: z.string().nullable().optional()
}).passthrough();

export type ChatMessageAttachmentDTO = z.infer<typeof chatMessageAttachmentSchema>;

export const chatMessageSchema = z.object({
  id: uuidSchema.or(z.string().min(1)),
  kind: z.string().min(1),
  text: z.string().default(""),
  createdAt: z.string()
}).passthrough();

export const panelProjectSchema = z.object({
  id: uuidSchema,
  name: z.string(),
  path: z.string(),
  defaultCLI: z.string(),
  createdAt: isoDateStringSchema,
  updatedAt: isoDateStringSchema,
  lastOpenedAt: isoDateStringSchema.nullable()
});

export const panelModelSchema = z.object({
  id: z.string(),
  title: z.string(),
  cli: z.string(),
  isDefault: z.boolean()
});

export const panelSessionSchema = z.object({
  id: uuidSchema,
  cli: z.string(),
  projectId: uuidSchema.nullable(),
  projectName: z.string(),
  projectPath: z.string(),
  title: z.string(),
  modelID: z.string(),
  runStatus: z.string(),
  statusText: z.string(),
  createdAt: isoDateStringSchema,
  updatedAt: isoDateStringSchema,
  lastCompletedAt: isoDateStringSchema.nullable(),
  queuedCount: z.number().int().nonnegative()
});

export const panelQueuedRequestSchema = z.object({
  id: uuidSchema,
  text: z.string(),
  displayText: z.string(),
  cli: z.string(),
  modelID: z.string(),
  permissionMode: z.string(),
  reasoningEffort: z.string(),
  projectId: uuidSchema,
  attachments: z.array(chatMessageAttachmentSchema)
});

export const panelStreamingTextSchema = z.object({
  messageId: uuidSchema,
  text: z.string(),
  status: z.string(),
  requestId: z.string().nullable()
});

export const panelComposerSchema = z.object({
  text: z.string(),
  cli: z.string(),
  modelID: z.string(),
  contextModelID: z.string().nullable(),
  permissionMode: z.string(),
  reasoningEffort: z.string(),
  attachments: z.array(chatMessageAttachmentSchema),
  isEnabled: z.boolean(),
  placeholder: z.string()
});

export const panelCapabilitySchema = z.object({
  cli: z.string(),
  executableAvailable: z.boolean(),
  supportsStreamJSONInput: z.boolean(),
  supportsAppServer: z.boolean(),
  errorMessage: z.string().nullable()
});

export const panelStateSnapshotSchema = z.object({
  revision: z.number().int().positive(),
  sessionId: uuidSchema.nullable(),
  projects: z.array(panelProjectSchema),
  models: z.array(panelModelSchema),
  sessions: z.array(panelSessionSchema),
  currentSessionId: uuidSchema.nullable(),
  messages: z.array(chatMessageSchema),
  queuedRequests: z.array(panelQueuedRequestSchema),
  streamingTexts: z.array(panelStreamingTextSchema),
  status: z.string(),
  statusText: z.string(),
  isAwaitingFirstModelOutput: z.boolean(),
  isLoadingHistory: z.boolean(),
  tokensUsed: z.number().int().nonnegative(),
  tokensTotal: z.number().int().nonnegative(),
  activeRunStartedAt: isoDateStringSchema.nullable(),
  isMirroringRemoteSession: z.boolean(),
  composer: panelComposerSchema,
  capabilities: z.array(panelCapabilitySchema)
});

export type PanelStateSnapshot = z.infer<typeof panelStateSnapshotSchema>;

export const nullableUUIDWrapperSchema = z.object({
  value: uuidSchema.nullable()
});

export const nullableDateWrapperSchema = z.object({
  value: isoDateStringSchema.nullable()
});

export const panelStatePatchSchema = z.object({
  revision: z.number().int().positive(),
  baseRevision: z.number().int().nonnegative(),
  sessionId: uuidSchema.nullable(),
  projects: z.array(panelProjectSchema).optional(),
  models: z.array(panelModelSchema).optional(),
  sessions: z.array(panelSessionSchema).optional(),
  currentSessionId: nullableUUIDWrapperSchema.optional(),
  messages: z.array(chatMessageSchema).optional(),
  queuedRequests: z.array(panelQueuedRequestSchema).optional(),
  streamingTexts: z.array(panelStreamingTextSchema).optional(),
  status: z.string().optional(),
  statusText: z.string().optional(),
  isAwaitingFirstModelOutput: z.boolean().optional(),
  isLoadingHistory: z.boolean().optional(),
  tokensUsed: z.number().int().nonnegative().optional(),
  tokensTotal: z.number().int().nonnegative().optional(),
  activeRunStartedAt: nullableDateWrapperSchema.optional(),
  isMirroringRemoteSession: z.boolean().optional(),
  composer: panelComposerSchema.optional(),
  capabilities: z.array(panelCapabilitySchema).optional()
});

export type PanelStatePatch = z.infer<typeof panelStatePatchSchema>;

export const panelStateEnvelopeSchema = z.object({
  type: z.literal(remoteVNCFrameType.panelState),
  kind: z.enum(["snapshot", "patch"]),
  sessionId: uuidSchema.nullable(),
  revision: z.number().int().positive(),
  snapshot: panelStateSnapshotSchema.nullable().optional(),
  patch: panelStatePatchSchema.nullable().optional()
}).superRefine((value, context) => {
  if (value.kind === "snapshot" && !value.snapshot) {
    context.addIssue({ code: z.ZodIssueCode.custom, message: "snapshot envelope requires snapshot" });
  }
  if (value.kind === "patch" && !value.patch) {
    context.addIssue({ code: z.ZodIssueCode.custom, message: "patch envelope requires patch" });
  }
});

export type PanelStateEnvelope = z.infer<typeof panelStateEnvelopeSchema>;

export const commandOpSchema = z.enum([
  "focusSession",
  "focusProject",
  "newDraftSession",
  "composerSet",
  "composerSetCLI",
  "composerSetModel",
  "composerSetPermissionMode",
  "composerSetReasoningEffort",
  "composerAttach",
  "composerRemoveAttach",
  "composerSend",
  "stop",
  "flushQueue",
  "interruptAndStartNext",
  "cancelQueued",
  "editQueued",
  "respondPermission",
  "respondInteractive",
  "requestSnapshot",
  "refreshCapabilities"
]);

export type CommandOp = z.infer<typeof commandOpSchema>;

export const interactiveResponseSchema = z.object({
  requestId: z.string().optional(),
  value: z.unknown().optional()
}).passthrough();

export const commandArgsSchema = z.object({
  text: z.string().optional(),
  cli: z.string().optional(),
  modelID: z.string().optional(),
  contextModelID: z.string().optional(),
  permissionMode: z.string().optional(),
  reasoningEffort: z.string().optional(),
  projectId: uuidSchema.optional(),
  sessionId: uuidSchema.optional(),
  requestId: z.string().optional(),
  permissionRequestId: z.string().optional(),
  decision: z.string().optional(),
  interactiveRequestId: z.string().optional(),
  interactiveResponse: interactiveResponseSchema.optional(),
  attachment: chatMessageAttachmentSchema.optional(),
  attachmentId: uuidSchema.optional(),
  sessionMode: z.string().optional(),
  resumeSessionID: z.string().optional(),
  appendRuleText: z.string().optional(),
  startQueuedAfterStop: z.boolean().optional(),
  expectedProjectId: uuidSchema.optional(),
  expectedSessionId: uuidSchema.optional()
}).passthrough();

export type CommandArgs = z.infer<typeof commandArgsSchema>;

export const commandSchema = z.object({
  type: z.literal(remoteVNCFrameType.command),
  commandId: uuidSchema,
  op: commandOpSchema,
  sessionId: uuidSchema.nullable().optional(),
  args: commandArgsSchema.default({})
});

export type RemoteCommand = z.infer<typeof commandSchema>;

export const commandAckSchema = z.object({
  type: z.literal(remoteVNCFrameType.commandAck),
  commandId: uuidSchema,
  status: z.enum(["ok", "rejected", "error"]),
  message: z.string().nullable().optional(),
  sessionId: uuidSchema.nullable().optional()
});

export type CommandAck = z.infer<typeof commandAckSchema>;

export const resumeRequestSchema = z.object({
  type: z.literal(remoteVNCFrameType.resume),
  sessionId: uuidSchema.nullable(),
  lastRevision: z.number().int().nonnegative().nullable()
});

export type ResumeRequest = z.infer<typeof resumeRequestSchema>;

export function makeCommand(op: CommandOp, args: CommandArgs = {}, sessionId: string | null = null): RemoteCommand {
  return commandSchema.parse({
    type: remoteVNCFrameType.command,
    commandId: crypto.randomUUID(),
    op,
    sessionId,
    args
  });
}

export function makeResumeRequest(sessionId: string | null, lastRevision: number | null): ResumeRequest {
  return resumeRequestSchema.parse({
    type: remoteVNCFrameType.resume,
    sessionId,
    lastRevision
  });
}
