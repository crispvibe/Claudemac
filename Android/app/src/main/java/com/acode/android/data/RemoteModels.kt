package com.acode.android.data

import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

data class RemoteAuthUser(
    val id: Int,
    val email: String,
    val phone: String?,
    val status: String,
) {
    val displayAccount: String get() = email.ifBlank { phone.orEmpty() }
}

data class RemoteAuthSession(
    val accessToken: String,
    val refreshToken: String,
    val expiresAt: Long,
    val user: RemoteAuthUser,
) {
    val isExpired: Boolean get() = expiresAt <= System.currentTimeMillis()
}

data class RemoteLegalDocument(
    val id: Int,
    val type: String,
    val platform: String,
    val version: String,
    val title: String,
    val contentFormat: String,
    val content: String,
    val published: Boolean,
)

data class RemoteAppUpdateInfo(
    val updateAvailable: Boolean,
    val latestVersion: String,
    val latestBuildNumber: String,
    val minimumVersion: String,
    val releaseNotes: String,
    val updateType: String,
    val downloadUrl: String,
    val appStoreUrl: String,
    val packageSha256: String,
    val packageFileSize: Long,
    val forceUpdate: Boolean,
)

data class RemoteLanEndpoint(
    val ip: String,
    val port: Int,
    val lastSeenAt: String? = null,
)

data class RemoteDeviceInfo(
    val id: Int,
    val userId: Int?,
    val deviceUid: String?,
    val deviceName: String,
    val deviceType: String?,
    val platform: String?,
    val approvalPolicy: String,
    val remoteEnabled: Boolean,
    val status: String,
    val online: Boolean,
    val lastSeenAt: String?,
    val lanEndpoint: RemoteLanEndpoint?,
    val transientToken: String?,
)

data class RemoteConnectionAttempt(
    val id: Int,
    val connectionId: Int?,
    val fromUserId: Int?,
    val fromDeviceId: Int?,
    val toUserId: Int?,
    val toDeviceId: Int?,
    val grantId: Int?,
    val status: String,
    val reason: String?,
    val completedAt: String?,
    val transport: String?,
    val endpoint: RemoteLanEndpoint?,
    val transientToken: String?,
)

data class RemoteIceServer(
    val urls: List<String>,
    val username: String?,
    val credential: String?,
    val realm: String?,
)

data class RemoteIceConfiguration(
    val iceServers: List<RemoteIceServer>,
)

data class RemoteSignalingPayload(
    val kind: String,
    val sdp: String? = null,
    val sdpMid: String? = null,
    val sdpMLineIndex: Int? = null,
    val candidate: String? = null,
    val message: String? = null,
)

data class RemoteConnectionMetricsRequest(
    val transport: String,
    val firstPacketLatencyMs: Int?,
    val stage: String?,
    val path: String?,
)

data class RemoteDeviceResolveResponse(
    val deviceId: Int,
    val deviceName: String,
    val platform: String,
    val approvalPolicy: String,
    val requiresConfirm: Boolean,
)

data class RemoteChatConfig(
    val macHost: String = "127.0.0.1",
    val port: Int = 18765,
    val token: String = "",
    val connectionId: Int? = null,
    val transport: String? = null,
    val reason: String? = null,
    val remoteAccessToken: String? = null,
    val remoteApiBaseUrl: String = "https://acode.anna.vin",
    val remoteRelayReady: Boolean = true,
) {
    val supportsDirectHttp: Boolean get() = macHost.isNotBlank() && port > 0 && token.isNotBlank()
    val isComplete: Boolean get() = supportsDirectHttp || !transport.isNullOrBlank()
    val baseUrl: String get() = "http://${macHost.trim()}:$port"
    val webSocketUrl: String
        get() {
            val base = "ws://${macHost.trim()}:$port/chat"
            return connectionId?.let { "$base?connection_id=$it" } ?: base
        }
}

data class RemoteProject(
    val id: String,
    val name: String,
    val path: String,
    val defaultCLI: String = "claude",
    val createdAt: String? = null,
    val updatedAt: String? = null,
    val lastOpenedAt: String? = null,
)

data class RemoteModel(
    val id: String,
    val title: String,
    val cli: String = "claude",
    val isDefault: Boolean = false,
)

data class RemoteSession(
    val id: String,
    val cli: String,
    val projectId: String?,
    val title: String,
    val modelID: String,
    val runStatus: String,
    val statusText: String,
    val queuedCount: Int,
    val projectName: String = "",
    val projectPath: String = "",
    val createdAt: String? = null,
    val updatedAt: String? = null,
    val lastCompletedAt: String? = null,
)

data class RemoteFileEntry(
    val name: String,
    val relativePath: String,
    val isDirectory: Boolean,
)

data class RemotePanelField<out T>(
    val isPresent: Boolean,
    val value: T?,
)

data class RemoteChatAttachment(
    val id: String = UUID.randomUUID().toString(),
    val kind: String = "file",
    val filename: String = "",
    val path: String = "",
    val thumbnailData: String? = null,
    val sizeBytes: Int = 0,
)

data class RemoteAttachmentUploadResponse(
    val filename: String,
    val path: String,
)

data class RemoteInteractiveOption(
    val id: String,
    val label: String,
    val detail: String = "",
)

data class RemoteInteractiveRequest(
    val id: String,
    val title: String = "",
    val prompt: String = "",
    val mode: String = "singleChoice",
    val options: List<RemoteInteractiveOption> = emptyList(),
    val allowCustomInput: Boolean = false,
    val placeholder: String = "",
    val status: String = "waiting",
)

data class RemoteInteractiveResponse(
    val requestID: String,
    val selectedOptionIDs: List<String> = emptyList(),
    val customText: String? = null,
)

data class RemoteQueuedRequest(
    val id: String,
    val text: String,
    val displayText: String = text,
    val cli: String = "claude",
    val modelID: String = "",
    val permissionMode: String = "autoEdit",
    val reasoningEffort: String = "high",
    val projectId: String = "",
    val attachments: List<RemoteChatAttachment> = emptyList(),
)

data class RemoteStreamingText(
    val messageId: String,
    val text: String,
    val status: String = "",
    val requestId: String? = null,
)

data class RemoteCapability(
    val cli: String,
    val executableAvailable: Boolean = false,
    val supportsStreamJSONInput: Boolean = false,
    val supportsAppServer: Boolean = false,
    val errorMessage: String? = null,
)

data class RemoteComposer(
    val text: String = "",
    val cli: String = "claude",
    val modelID: String = "",
    val permissionMode: String = "autoEdit",
    val reasoningEffort: String = "high",
    val isEnabled: Boolean = true,
    val placeholder: String = "输入消息...",
    val contextModelID: String? = null,
    val attachments: List<RemoteChatAttachment> = emptyList(),
)

data class RemoteChatMessage(
    val id: String = UUID.randomUUID().toString(),
    val kind: String,
    val text: String,
    val status: String = "",
    val sessionID: String? = null,
    val title: String = "",
    val subtitle: String = "",
    val createdAt: String? = null,
    val parentUserMessageID: String? = null,
    val requestID: String? = null,
    val isStreaming: Boolean = false,
    val interactiveRequest: RemoteInteractiveRequest? = null,
    val interactive: RemoteInteractiveRequest? = interactiveRequest,
    val appendRuleText: String? = null,
    val outputTokenCount: Int? = null,
    val token: Int? = outputTokenCount,
    val attachments: List<RemoteChatAttachment> = emptyList(),
) {
    val fromUser: Boolean get() = kind == "user"
}

data class RemotePanelSnapshot(
    val revision: Int,
    val sessionId: String?,
    val projects: List<RemoteProject>,
    val models: List<RemoteModel>,
    val sessions: List<RemoteSession>,
    val currentSessionId: String?,
    val messages: List<RemoteChatMessage>,
    val status: String,
    val statusText: String,
    val isAwaitingFirstModelOutput: Boolean,
    val isLoadingHistory: Boolean,
    val composer: RemoteComposer,
    val queuedRequests: List<RemoteQueuedRequest> = emptyList(),
    val streamingTexts: List<RemoteStreamingText> = emptyList(),
    val tokensUsed: Int = 0,
    val tokensTotal: Int = 0,
    val activeRunStartedAt: String? = null,
    val isMirroringRemoteSession: Boolean = false,
    val capabilities: List<RemoteCapability> = emptyList(),
)

data class RemotePanelPatch(
    val revision: Int,
    val baseRevision: Int,
    val sessionId: String?,
    val projects: List<RemoteProject>?,
    val models: List<RemoteModel>?,
    val sessions: List<RemoteSession>?,
    val currentSessionId: String?,
    val messages: List<RemoteChatMessage>?,
    val status: String?,
    val statusText: String?,
    val isAwaitingFirstModelOutput: Boolean?,
    val isLoadingHistory: Boolean?,
    val composer: RemoteComposer?,
    val baseRevisionField: RemotePanelField<Int>? = null,
    val currentSessionIdField: RemotePanelField<String>? = null,
    val queuedRequests: List<RemoteQueuedRequest>? = null,
    val streamingTexts: List<RemoteStreamingText>? = null,
    val tokensUsed: Int? = null,
    val tokensTotal: Int? = null,
    val activeRunStartedAt: String? = null,
    val activeRunStartedAtField: RemotePanelField<String>? = null,
    val isMirroringRemoteSession: Boolean? = null,
    val capabilities: List<RemoteCapability>? = null,
)

data class RemoteProjectFiles(
    val projectId: String,
    val path: String,
    val parentPath: String?,
    val entries: List<RemoteFileEntry>,
)

internal fun JSONObject.stringOrNull(vararg keys: String): String? {
    for (key in keys) {
        if (has(key) && !isNull(key)) return optString(key)
    }
    return null
}

internal fun JSONObject.intOrNull(vararg keys: String): Int? {
    for (key in keys) {
        if (has(key) && !isNull(key)) return optInt(key)
    }
    return null
}

internal fun JSONObject.boolOrDefault(default: Boolean, vararg keys: String): Boolean {
    for (key in keys) {
        if (has(key) && !isNull(key)) return optBoolean(key)
    }
    return default
}

internal fun JSONObject.booleanOrNull(vararg keys: String): Boolean? {
    for (key in keys) {
        if (has(key) && !isNull(key)) return optBoolean(key)
    }
    return null
}

internal fun JSONObject.stringField(key: String): RemotePanelField<String>? {
    if (!has(key)) return null
    return RemotePanelField(isPresent = true, value = if (isNull(key)) null else optString(key))
}

internal fun JSONObject.intField(key: String): RemotePanelField<Int>? {
    if (!has(key)) return null
    return RemotePanelField(isPresent = true, value = if (isNull(key)) null else optInt(key))
}

internal fun JSONArray.objects(): List<JSONObject> = List(length()) { index -> optJSONObject(index) ?: JSONObject() }

fun JSONObject.toAuthSession(): RemoteAuthSession {
    val user = optJSONObject("user") ?: JSONObject()
    return RemoteAuthSession(
        accessToken = optString("accessToken"),
        refreshToken = optString("refreshToken"),
        expiresAt = optLong("expiresAt"),
        user = RemoteAuthUser(
            id = user.optInt("id"),
            email = user.optString("email", user.optString("phone")),
            phone = user.stringOrNull("phone"),
            status = user.optString("status", "active"),
        ),
    )
}

fun JSONObject.toLegalDocument(): RemoteLegalDocument = RemoteLegalDocument(
    id = optInt("id"),
    type = optString("type"),
    platform = optString("platform"),
    version = optString("version"),
    title = optString("title"),
    contentFormat = optString("contentFormat", "markdown"),
    content = optString("content"),
    published = optBoolean("published", true),
)

fun JSONObject.toAppUpdateInfo(): RemoteAppUpdateInfo = RemoteAppUpdateInfo(
    updateAvailable = optBoolean("updateAvailable", false),
    latestVersion = optString("latestVersion"),
    latestBuildNumber = optString("latestBuildNumber"),
    minimumVersion = optString("minimumVersion"),
    releaseNotes = optString("releaseNotes"),
    updateType = optString("updateType", "link"),
    downloadUrl = optString("downloadUrl"),
    appStoreUrl = optString("appStoreUrl"),
    packageSha256 = optString("packageSha256"),
    packageFileSize = optLong("packageFileSize", 0),
    forceUpdate = optBoolean("forceUpdate", false),
)

fun JSONObject.toDeviceInfo(): RemoteDeviceInfo {
    val endpointJson = optJSONObject("lanEndpoint") ?: optJSONObject("lan_endpoint")
    return RemoteDeviceInfo(
        id = optInt("id"),
        userId = intOrNull("userId", "user_id"),
        deviceUid = stringOrNull("deviceUid", "deviceUID", "device_uid"),
        deviceName = optString("deviceName", "我的电脑"),
        deviceType = stringOrNull("deviceType", "device_type"),
        platform = stringOrNull("platform"),
        approvalPolicy = optString("approvalPolicy", optString("approval_policy", "always_ask")),
        remoteEnabled = boolOrDefault(true, "remoteEnabled", "remote_enabled"),
        status = optString("status", "active"),
        online = optBoolean("online", false),
        lastSeenAt = stringOrNull("lastSeenAt", "last_seen_at"),
        lanEndpoint = endpointJson?.toLanEndpoint(),
        transientToken = stringOrNull("transientToken", "transient_token"),
    )
}

fun JSONObject.toConnectionAttempt(): RemoteConnectionAttempt = RemoteConnectionAttempt(
    id = optInt("id"),
    connectionId = intOrNull("connectionId", "connection_id"),
    fromUserId = intOrNull("fromUserId", "from_user_id"),
    fromDeviceId = intOrNull("fromDeviceId", "from_device_id"),
    toUserId = intOrNull("toUserId", "to_user_id"),
    toDeviceId = intOrNull("toDeviceId", "to_device_id"),
    grantId = intOrNull("grantId", "grant_id"),
    status = optString("status"),
    reason = stringOrNull("reason"),
    completedAt = stringOrNull("completedAt", "completed_at"),
    transport = stringOrNull("transport"),
    endpoint = optJSONObject("endpoint")?.toLanEndpoint(),
    transientToken = stringOrNull("transientToken", "transient_token"),
)

fun JSONObject.toDeviceResolveResponse(): RemoteDeviceResolveResponse = RemoteDeviceResolveResponse(
    deviceId = optInt("deviceId"),
    deviceName = optString("deviceName", "目标设备"),
    platform = optString("platform", "macos"),
    approvalPolicy = optString("approvalPolicy", "always_ask"),
    requiresConfirm = optBoolean("requiresConfirm", true),
)

fun JSONObject.toLanEndpoint(): RemoteLanEndpoint = RemoteLanEndpoint(
    ip = optString("ip"),
    port = optInt("port"),
    lastSeenAt = stringOrNull("lastSeenAt", "last_seen_at"),
)

fun JSONObject.toIceConfiguration(): RemoteIceConfiguration {
    val servers = optJSONArray("iceServers") ?: optJSONArray("ice_servers") ?: JSONArray()
    return RemoteIceConfiguration(iceServers = servers.objects().map { it.toIceServer() })
}

private fun JSONObject.toIceServer(): RemoteIceServer {
    val rawUrls = opt("urls")
    val urls = when (rawUrls) {
        is JSONArray -> List(rawUrls.length()) { index -> rawUrls.optString(index) }.filter { it.isNotBlank() }
        is String -> listOf(rawUrls).filter { it.isNotBlank() }
        else -> emptyList()
    }
    return RemoteIceServer(
        urls = urls,
        username = stringOrNull("username"),
        credential = stringOrNull("credential"),
        realm = stringOrNull("realm"),
    )
}

fun RemoteSignalingPayload.toJson(): JSONObject = JSONObject().apply {
    put("kind", kind)
    sdp?.let { put("sdp", it) }
    sdpMid?.let { put("sdpMid", it) }
    sdpMLineIndex?.let { put("sdpMLineIndex", it) }
    candidate?.let { put("candidate", it) }
    message?.let { put("message", it) }
}

fun JSONObject.toSignalingPayload(): RemoteSignalingPayload = RemoteSignalingPayload(
    kind = optString("kind"),
    sdp = stringOrNull("sdp"),
    sdpMid = stringOrNull("sdpMid", "sdp_mid"),
    sdpMLineIndex = intOrNull("sdpMLineIndex", "sdp_m_line_index"),
    candidate = stringOrNull("candidate"),
    message = stringOrNull("message"),
)

fun JSONObject.toPanelSnapshot(): RemotePanelSnapshot = RemotePanelSnapshot(
    revision = optInt("revision", 1),
    sessionId = stringOrNull("sessionId"),
    projects = optJSONArray("projects")?.objects()?.map { it.toRemoteProject() }.orEmpty(),
    models = optJSONArray("models")?.objects()?.map { it.toRemoteModel() }.orEmpty(),
    sessions = optJSONArray("sessions")?.objects()?.map { it.toRemoteSession() }.orEmpty(),
    currentSessionId = stringOrNull("currentSessionId"),
    messages = optJSONArray("messages")?.objects()?.map { it.toRemoteMessage() }.orEmpty(),
    queuedRequests = optJSONArray("queuedRequests")?.objects()?.map { it.toRemoteQueuedRequest() }.orEmpty(),
    streamingTexts = optJSONArray("streamingTexts")?.objects()?.map { it.toRemoteStreamingText() }.orEmpty(),
    status = optString("status"),
    statusText = optString("statusText"),
    isAwaitingFirstModelOutput = optBoolean("isAwaitingFirstModelOutput", false),
    isLoadingHistory = optBoolean("isLoadingHistory", false),
    tokensUsed = optInt("tokensUsed", 0),
    tokensTotal = optInt("tokensTotal", 0),
    activeRunStartedAt = stringOrNull("activeRunStartedAt"),
    isMirroringRemoteSession = optBoolean("isMirroringRemoteSession", false),
    composer = optJSONObject("composer")?.toRemoteComposer() ?: RemoteComposer(),
    capabilities = optJSONArray("capabilities")?.objects()?.map { it.toRemoteCapability() }.orEmpty(),
)

fun JSONObject.toPanelPatch(): RemotePanelPatch = RemotePanelPatch(
    revision = optInt("revision", 1),
    baseRevision = intOrNull("baseRevision") ?: 0,
    baseRevisionField = intField("baseRevision"),
    sessionId = stringOrNull("sessionId"),
    projects = optJSONArray("projects")?.objects()?.map { it.toRemoteProject() },
    models = optJSONArray("models")?.objects()?.map { it.toRemoteModel() },
    sessions = optJSONArray("sessions")?.objects()?.map { it.toRemoteSession() },
    currentSessionId = stringOrNull("currentSessionId"),
    currentSessionIdField = stringField("currentSessionId"),
    messages = optJSONArray("messages")?.objects()?.map { it.toRemoteMessage() },
    queuedRequests = optJSONArray("queuedRequests")?.objects()?.map { it.toRemoteQueuedRequest() },
    streamingTexts = optJSONArray("streamingTexts")?.objects()?.map { it.toRemoteStreamingText() },
    status = stringOrNull("status"),
    statusText = stringOrNull("statusText"),
    isAwaitingFirstModelOutput = if (has("isAwaitingFirstModelOutput")) optBoolean("isAwaitingFirstModelOutput") else null,
    isLoadingHistory = if (has("isLoadingHistory")) optBoolean("isLoadingHistory") else null,
    tokensUsed = intOrNull("tokensUsed"),
    tokensTotal = intOrNull("tokensTotal"),
    activeRunStartedAt = stringOrNull("activeRunStartedAt"),
    activeRunStartedAtField = stringField("activeRunStartedAt"),
    isMirroringRemoteSession = booleanOrNull("isMirroringRemoteSession"),
    composer = optJSONObject("composer")?.toRemoteComposer(),
    capabilities = optJSONArray("capabilities")?.objects()?.map { it.toRemoteCapability() },
)

fun RemotePanelSnapshot.applyPatch(patch: RemotePanelPatch): RemotePanelSnapshot? {
    if (patch.baseRevision != revision) return null
    return copy(
        revision = patch.revision,
        sessionId = patch.sessionId ?: sessionId,
        projects = patch.projects ?: projects,
        models = patch.models ?: models,
        sessions = patch.sessions ?: sessions,
        currentSessionId = when {
            patch.currentSessionIdField?.isPresent == true -> patch.currentSessionIdField.value
            patch.currentSessionId != null -> patch.currentSessionId
            else -> currentSessionId
        },
        messages = patch.messages ?: messages,
        queuedRequests = patch.queuedRequests ?: queuedRequests,
        streamingTexts = patch.streamingTexts ?: streamingTexts,
        status = patch.status ?: status,
        statusText = patch.statusText ?: statusText,
        isAwaitingFirstModelOutput = patch.isAwaitingFirstModelOutput ?: isAwaitingFirstModelOutput,
        isLoadingHistory = patch.isLoadingHistory ?: isLoadingHistory,
        tokensUsed = patch.tokensUsed ?: tokensUsed,
        tokensTotal = patch.tokensTotal ?: tokensTotal,
        activeRunStartedAt = when {
            patch.activeRunStartedAtField?.isPresent == true -> patch.activeRunStartedAtField.value
            patch.activeRunStartedAt != null -> patch.activeRunStartedAt
            else -> activeRunStartedAt
        },
        isMirroringRemoteSession = patch.isMirroringRemoteSession ?: isMirroringRemoteSession,
        composer = patch.composer ?: composer,
        capabilities = patch.capabilities ?: capabilities,
    )
}

private fun JSONObject.toRemoteProject(): RemoteProject = RemoteProject(
    id = optString("id"),
    name = optString("name"),
    path = optString("path"),
    defaultCLI = optString("defaultCLI", "claude"),
    createdAt = stringOrNull("createdAt"),
    updatedAt = stringOrNull("updatedAt"),
    lastOpenedAt = stringOrNull("lastOpenedAt"),
)

private fun JSONObject.toRemoteModel(): RemoteModel = RemoteModel(
    id = optString("id"),
    title = optString("title", optString("id")),
    cli = optString("cli", "claude"),
    isDefault = optBoolean("isDefault", false),
)

private fun JSONObject.toRemoteSession(): RemoteSession = RemoteSession(
    id = optString("id"),
    cli = optString("cli", "claude"),
    projectId = stringOrNull("projectId"),
    projectName = optString("projectName"),
    projectPath = optString("projectPath"),
    title = optString("title", "新对话"),
    modelID = optString("modelID"),
    runStatus = optString("runStatus"),
    statusText = optString("statusText"),
    createdAt = stringOrNull("createdAt"),
    updatedAt = stringOrNull("updatedAt"),
    lastCompletedAt = stringOrNull("lastCompletedAt"),
    queuedCount = optInt("queuedCount", 0),
)

private fun JSONObject.toRemoteMessage(): RemoteChatMessage = RemoteChatMessage(
    id = optString("id", UUID.randomUUID().toString()),
    sessionID = stringOrNull("sessionID", "sessionId"),
    kind = optString("kind", optString("role", "assistant")),
    title = optString("title"),
    subtitle = optString("subtitle"),
    text = optString("text", optString("content")),
    status = optString("status"),
    createdAt = stringOrNull("createdAt"),
    parentUserMessageID = stringOrNull("parentUserMessageID", "parentUserMessageId"),
    requestID = stringOrNull("requestID", "requestId"),
    isStreaming = optBoolean("isStreaming", false),
    interactiveRequest = (optJSONObject("interactiveRequest") ?: optJSONObject("interactive"))?.toRemoteInteractiveRequest(),
    appendRuleText = stringOrNull("appendRuleText"),
    outputTokenCount = intOrNull("outputTokenCount", "token", "tokenCount"),
    attachments = optJSONArray("attachments")?.objects()?.map { it.toRemoteChatAttachment() }.orEmpty(),
)

private fun JSONObject.toRemoteComposer(): RemoteComposer = RemoteComposer(
    text = optString("text"),
    cli = optString("cli", "claude"),
    modelID = optString("modelID"),
    contextModelID = stringOrNull("contextModelID", "contextModelId"),
    permissionMode = optString("permissionMode", "autoEdit"),
    reasoningEffort = optString("reasoningEffort", "high"),
    attachments = optJSONArray("attachments")?.objects()?.map { it.toRemoteChatAttachment() }.orEmpty(),
    isEnabled = optBoolean("isEnabled", true),
    placeholder = optString("placeholder", "输入消息..."),
)

private fun JSONObject.toRemoteChatAttachment(): RemoteChatAttachment = RemoteChatAttachment(
    id = optString("id", UUID.randomUUID().toString()),
    kind = optString("kind", "file"),
    filename = optString("filename"),
    path = optString("path"),
    thumbnailData = stringOrNull("thumbnailData"),
    sizeBytes = optInt("sizeBytes", 0),
)

fun JSONObject.toAttachmentUploadResponse(): RemoteAttachmentUploadResponse = RemoteAttachmentUploadResponse(
    filename = optString("filename"),
    path = optString("path"),
)

fun RemoteChatAttachment.toJson(): JSONObject = JSONObject().apply {
    put("id", id)
    put("kind", kind)
    put("filename", filename)
    put("path", path)
    thumbnailData?.let { put("thumbnailData", it) }
    if (sizeBytes > 0) put("sizeBytes", sizeBytes)
}

private fun JSONObject.toRemoteInteractiveOption(): RemoteInteractiveOption = RemoteInteractiveOption(
    id = optString("id"),
    label = optString("label"),
    detail = optString("detail"),
)

private fun JSONObject.toRemoteInteractiveRequest(): RemoteInteractiveRequest = RemoteInteractiveRequest(
    id = optString("id"),
    title = optString("title"),
    prompt = optString("prompt"),
    mode = optString("mode", "singleChoice"),
    options = optJSONArray("options")?.objects()?.map { it.toRemoteInteractiveOption() }.orEmpty(),
    allowCustomInput = optBoolean("allowCustomInput", false),
    placeholder = optString("placeholder"),
    status = optString("status", "waiting"),
)

private fun JSONObject.toRemoteQueuedRequest(): RemoteQueuedRequest = RemoteQueuedRequest(
    id = optString("id"),
    text = optString("text"),
    displayText = optString("displayText", optString("text")),
    cli = optString("cli", "claude"),
    modelID = optString("modelID"),
    permissionMode = optString("permissionMode", "autoEdit"),
    reasoningEffort = optString("reasoningEffort", "high"),
    projectId = optString("projectId"),
    attachments = optJSONArray("attachments")?.objects()?.map { it.toRemoteChatAttachment() }.orEmpty(),
)

private fun JSONObject.toRemoteStreamingText(): RemoteStreamingText = RemoteStreamingText(
    messageId = optString("messageId"),
    text = optString("text"),
    status = optString("status"),
    requestId = stringOrNull("requestId"),
)

private fun JSONObject.toRemoteCapability(): RemoteCapability = RemoteCapability(
    cli = optString("cli"),
    executableAvailable = optBoolean("executableAvailable", false),
    supportsStreamJSONInput = optBoolean("supportsStreamJSONInput", false),
    supportsAppServer = optBoolean("supportsAppServer", false),
    errorMessage = stringOrNull("errorMessage"),
)
