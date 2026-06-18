package com.codevoke.android.ui.state

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.codevoke.android.data.LocalDeviceIdentity
import com.codevoke.android.data.LocalDeviceIdentityStore
import com.codevoke.android.data.RemoteApiClient
import com.codevoke.android.data.RemoteChatAttachment
import com.codevoke.android.data.RemoteChatClient
import com.codevoke.android.data.RemoteChatConfig
import com.codevoke.android.data.RemoteComposer
import com.codevoke.android.data.RemoteConnectionAttempt
import com.codevoke.android.data.RemoteConnectionMetricsRequest
import com.codevoke.android.data.RemoteDeviceInfo
import com.codevoke.android.data.RemoteDeviceResolveResponse
import com.codevoke.android.data.RemoteFileEntry
import com.codevoke.android.data.RemoteInteractiveResponse
import com.codevoke.android.data.RemoteLanClient
import com.codevoke.android.data.RemoteLegalDocument
import com.codevoke.android.data.RemoteModel
import com.codevoke.android.data.RemotePanelSnapshot
import com.codevoke.android.data.RemoteProject
import com.codevoke.android.data.RemoteQueuedRequest
import com.codevoke.android.data.RemoteSession
import com.codevoke.android.data.RemoteSessionStore
import com.codevoke.android.data.RemoteSignalingClient
import com.codevoke.android.data.RemoteStreamingText
import com.codevoke.android.data.LanNetworkSelector
import com.codevoke.android.data.LanSignalingResolver
import com.codevoke.android.data.LanSubnetProbe
import com.codevoke.android.data.RemoteTunnelTransport
import com.codevoke.android.data.RemoteWebRtcTransport
import com.codevoke.android.data.applyPatch
import com.codevoke.android.data.toJson
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import org.json.JSONObject
import java.util.UUID

enum class AuthGateState {
    Checking,
    Unauthenticated,
    Authenticated,
}

data class AuthUiState(
    val gateState: AuthGateState = AuthGateState.Checking,
    val email: String = "",
    val password: String = "",
    val confirmPassword: String = "",
    val verificationCode: String = "",
    val forgotPassword: String = "",
    val forgotConfirmPassword: String = "",
    val currentPassword: String = "",
    val newPassword: String = "",
    val newPasswordConfirm: String = "",
    val deletionConfirmAccount: String = "",
    val deletionConfirmDestroy: String = "",
    val deletionConfirmWaiveRights: String = "",
    val deletionReason: String = "",
    val agreed: Boolean = false,
    val submitting: Boolean = false,
    val registerCodeSending: Boolean = false,
    val registerCodeCooldown: Int = 0,
    val passwordResetCodeSending: Boolean = false,
    val passwordResetCodeCooldown: Int = 0,
    val message: String? = null,
    val account: String = "",
    val legalDocuments: Map<String, RemoteLegalDocument> = emptyMap(),
    val selectedLegalDocument: RemoteLegalDocument? = null,
)

data class DeviceUiState(
    val devices: List<RemoteDeviceInfo> = emptyList(),
    val loading: Boolean = false,
    val resolvingCode: Boolean = false,
    val connecting: Boolean = false,
    val deviceCode: String = "",
    val resolvedDevice: RemoteDeviceResolveResponse? = null,
    val message: String? = null,
    val connectedDeviceId: Int? = null,
    val connectedDeviceName: String? = null,
    val connectedTransport: String? = null,
)

data class ChatUiState(
    val config: RemoteChatConfig = RemoteChatConfig(),
    val connectionStatus: String = "未连接",
    val lastError: String? = null,
    val projects: List<RemoteProject> = emptyList(),
    val models: List<RemoteModel> = emptyList(),
    val sessions: List<RemoteSession> = emptyList(),
    val selectedProjectId: String? = null,
    val selectedSessionId: String? = null,
    val selectedModelId: String = "",
    val messages: List<com.codevoke.android.data.RemoteChatMessage> = emptyList(),
    val streamingTexts: List<RemoteStreamingText> = emptyList(),
    val files: List<RemoteFileEntry> = emptyList(),
    val fileError: String? = null,
    val currentFilePath: String = "",
    val parentFilePath: String? = null,
    val inputText: String = "",
    val composer: RemoteComposer = RemoteComposer(),
    val attachments: List<RemoteChatAttachment> = emptyList(),
    val queuedRequests: List<RemoteQueuedRequest> = emptyList(),
    val runtimeStatus: String = "",
    val isAwaitingFirstModelOutput: Boolean = false,
    val isLoadingHistory: Boolean = false,
    val tokensUsed: Int = 0,
    val tokensTotal: Int = 0,
    val isRefreshing: Boolean = false,
    val isLoadingFiles: Boolean = false,
    val isUploadingAttachment: Boolean = false,
) {
    val selectedProject: RemoteProject? get() = projects.firstOrNull { it.id == selectedProjectId } ?: projects.firstOrNull()
    val filteredSessions: List<RemoteSession> get() = selectedProject?.let { project -> sessions.filter { it.projectId == project.id } } ?: sessions
    val selectedModelTitle: String get() = models.firstOrNull { it.id == selectedModelId }?.title ?: selectedModelId.ifBlank { "默认模型" }
    val canSendDraft: Boolean get() = inputText.trim().isNotEmpty() || attachments.isNotEmpty()
}

private data class PendingRemoteCommand(
    val commandId: String,
    val op: String,
    val sessionId: String?,
    val args: JSONObject,
)

class CodevokeViewModel(application: Application) : AndroidViewModel(application) {
    var auth by mutableStateOf(AuthUiState())
        private set
    var devices by mutableStateOf(DeviceUiState())
        private set
    var chat by mutableStateOf(ChatUiState())
        private set
    val transportLabel: String
        get() = when (chat.config.transport) {
            "lan" -> "局域网"
            "public" -> "公网直连"
            "p2p" -> "跨网 P2P"
            "tunnel" -> "跨网通道"
            else -> ""
        }

    private val api = RemoteApiClient()
    private val sessionStore = RemoteSessionStore(application)
    private val identityStore = LocalDeviceIdentityStore(application)
    private val remoteChatClient = RemoteChatClient()
    private val signalingClient = RemoteSignalingClient()
    private var remoteWebRtcTransport: RemoteWebRtcTransport? = null
    private var remoteTunnelTransport: RemoteTunnelTransport? = null
    private var snapshot: RemotePanelSnapshot? = null
    private val bufferedDecisions = mutableMapOf<Int, RemoteConnectionAttempt>()
    private val pendingCommands = mutableListOf<PendingRemoteCommand>()
    private var pendingProjectFocusJob: Job? = null
    private var pendingSessionFocusJob: Job? = null
    private var registerCodeCooldownJob: Job? = null
    private var passwordResetCodeCooldownJob: Job? = null
    private var currentConnectStartedAtMs: Long? = null
    private var didReportFirstPanelStateLatency = false
    private var pendingAttachmentUploadCount = 0
    private val maxAttachmentBytes = 10 * 1024 * 1024
    private val maxTotalAttachmentBytes = 20 * 1024 * 1024

    init {
        bindChatClient()
        bindSignalingClient()
        bootstrap()
    }

    private fun bootstrap() {
        viewModelScope.launch {
            val saved = sessionStore.load()
            if (saved == null) {
                auth = auth.copy(gateState = AuthGateState.Unauthenticated)
                loadLegalDocuments()
                return@launch
            }
            runCatching {
                val session = if (saved.isExpired) api.refresh(saved.refreshToken) else saved
                sessionStore.save(session)
                registerLocalDevice(session.accessToken)
                auth = auth.copy(gateState = AuthGateState.Authenticated, account = session.user.displayAccount, email = session.user.email)
                loadRemoteDevices()
            }.onFailure {
                sessionStore.clear()
                auth = auth.copy(gateState = AuthGateState.Unauthenticated, message = userMessage(it))
            }
            loadLegalDocuments()
        }
    }

    fun updateEmail(value: String) {
        auth = auth.copy(email = value, message = null)
    }

    fun updatePassword(value: String) {
        auth = auth.copy(password = value, message = null)
    }

    fun updateConfirmPassword(value: String) {
        auth = auth.copy(confirmPassword = value, message = null)
    }

    fun updateVerificationCode(value: String) {
        auth = auth.copy(verificationCode = value, message = null)
    }

    fun updateForgotPassword(value: String) {
        auth = auth.copy(forgotPassword = value, message = null)
    }

    fun updateForgotConfirmPassword(value: String) {
        auth = auth.copy(forgotConfirmPassword = value, message = null)
    }

    fun updateCurrentPassword(value: String) {
        auth = auth.copy(currentPassword = value, message = null)
    }

    fun updateNewPassword(value: String) {
        auth = auth.copy(newPassword = value, message = null)
    }

    fun updateNewPasswordConfirm(value: String) {
        auth = auth.copy(newPasswordConfirm = value, message = null)
    }

    fun updateDeletionConfirmAccount(value: String) {
        auth = auth.copy(deletionConfirmAccount = value, message = null)
    }

    fun updateDeletionConfirmDestroy(value: String) {
        auth = auth.copy(deletionConfirmDestroy = value, message = null)
    }

    fun updateDeletionConfirmWaiveRights(value: String) {
        auth = auth.copy(deletionConfirmWaiveRights = value, message = null)
    }

    fun updateDeletionReason(value: String) {
        auth = auth.copy(deletionReason = value, message = null)
    }

    fun toggleAgreement() {
        auth = auth.copy(agreed = !auth.agreed)
    }

    fun requestLogin(onSuccess: () -> Unit) {
        val email = auth.email.trim()
        val password = auth.password
        if (email.isBlank() || password.isBlank()) {
            auth = auth.copy(message = "请输入邮箱和密码。")
            return
        }
        if (!auth.agreed) {
            auth = auth.copy(message = "请先勾选用户协议和隐私政策。")
            return
        }
        viewModelScope.launch {
            auth = auth.copy(submitting = true, message = null)
            runCatching { api.login(email, password) }
                .onSuccess { session ->
                    sessionStore.save(session)
                    registerLocalDevice(session.accessToken)
                    submitLegalConsents(session.accessToken)
                    auth = auth.copy(
                        gateState = AuthGateState.Authenticated,
                        submitting = false,
                        password = "",
                        account = session.user.displayAccount,
                    )
                    loadRemoteDevices()
                    onSuccess()
                }
                .onFailure { auth = auth.copy(submitting = false, message = userMessage(it, "账号不存在或密码错误。")) }
        }
    }

    fun requestRegisterCode() {
        val email = auth.email.trim()
        if (auth.registerCodeSending || auth.registerCodeCooldown > 0) return
        if (email.isBlank()) {
            auth = auth.copy(message = "请输入邮箱。")
            return
        }
        viewModelScope.launch {
            auth = auth.copy(registerCodeSending = true, message = null)
            runCatching { api.requestRegisterCode(email) }
                .onSuccess {
                    auth = auth.copy(registerCodeSending = false, message = "验证码已发送。")
                    startRegisterCodeCooldown()
                }
                .onFailure { auth = auth.copy(registerCodeSending = false, message = userMessage(it)) }
        }
    }

    fun requestRegister(onSuccess: () -> Unit) {
        val email = auth.email.trim()
        if (email.isBlank() || auth.password.isBlank() || auth.verificationCode.isBlank()) {
            auth = auth.copy(message = "请完整填写邮箱、验证码和密码。")
            return
        }
        if (auth.password != auth.confirmPassword) {
            auth = auth.copy(message = "两次密码不一致。")
            return
        }
        if (!auth.agreed) {
            auth = auth.copy(message = "请先勾选用户协议和隐私政策。")
            return
        }
        viewModelScope.launch {
            auth = auth.copy(submitting = true, message = null)
            runCatching { api.register(email, auth.password, auth.verificationCode) }
                .onSuccess { session ->
                    sessionStore.save(session)
                    registerLocalDevice(session.accessToken)
                    submitLegalConsents(session.accessToken)
                    auth = auth.copy(gateState = AuthGateState.Authenticated, submitting = false, account = session.user.displayAccount)
                    loadRemoteDevices()
                    onSuccess()
                }
                .onFailure { auth = auth.copy(submitting = false, message = userMessage(it, "账号创建失败，请检查邮箱。")) }
        }
    }

    fun requestPasswordResetCode() {
        val email = auth.email.trim()
        if (auth.passwordResetCodeSending || auth.passwordResetCodeCooldown > 0) return
        if (email.isBlank()) {
            auth = auth.copy(message = "请输入邮箱。")
            return
        }
        viewModelScope.launch {
            auth = auth.copy(passwordResetCodeSending = true, message = null)
            runCatching { api.requestPasswordResetCode(email) }
                .onSuccess {
                    auth = auth.copy(passwordResetCodeSending = false, message = "验证码已发送。")
                    startPasswordResetCodeCooldown()
                }
                .onFailure { auth = auth.copy(passwordResetCodeSending = false, message = userMessage(it)) }
        }
    }

    fun requestPasswordReset(onSuccess: () -> Unit) {
        val email = auth.email.trim()
        if (email.isBlank() || auth.forgotPassword.isBlank() || auth.verificationCode.isBlank()) {
            auth = auth.copy(message = "请完整填写邮箱、验证码和新密码。")
            return
        }
        if (auth.forgotPassword != auth.forgotConfirmPassword) {
            auth = auth.copy(message = "两次密码不一致。")
            return
        }
        viewModelScope.launch {
            auth = auth.copy(submitting = true, message = null)
            runCatching { api.resetPassword(email, auth.forgotPassword, auth.verificationCode) }
                .onSuccess {
                    auth = auth.copy(submitting = false, message = "密码已重置，请返回登录。", password = "")
                    onSuccess()
                }
                .onFailure { auth = auth.copy(submitting = false, message = userMessage(it, "密码重置失败。")) }
        }
    }

    fun logout() {
        remoteChatClient.disconnect()
        remoteWebRtcTransport?.disconnect()
        remoteWebRtcTransport = null
        remoteTunnelTransport?.disconnect()
        remoteTunnelTransport = null
        signalingClient.stop()
        sessionStore.clear()
        auth = AuthUiState(gateState = AuthGateState.Unauthenticated)
        devices = DeviceUiState()
        chat = ChatUiState()
    }

    fun changePassword(onLoggedOut: () -> Unit) {
        val session = sessionStore.load()
        if (session == null) {
            auth = auth.copy(message = "登录状态已失效，请重新登录。")
            logout()
            onLoggedOut()
            return
        }
        if (auth.currentPassword.isBlank() || auth.newPassword.isBlank()) {
            auth = auth.copy(message = "请填写当前密码和新密码。")
            return
        }
        if (auth.newPassword != auth.newPasswordConfirm) {
            auth = auth.copy(message = "两次密码不一致。")
            return
        }
        viewModelScope.launch {
            auth = auth.copy(submitting = true, message = null)
            runCatching { api.changePassword(auth.currentPassword, auth.newPassword, session.accessToken) }
                .onSuccess {
                    auth = auth.copy(submitting = false, message = "密码已修改，请重新登录。")
                    logout()
                    onLoggedOut()
                }
                .onFailure { auth = auth.copy(submitting = false, message = userMessage(it, "密码修改失败。")) }
        }
    }

    fun deleteAccount(onLoggedOut: () -> Unit) {
        val session = sessionStore.load()
        if (session == null) {
            auth = auth.copy(message = "登录状态已失效，请重新登录。")
            logout()
            onLoggedOut()
            return
        }
        if (
            auth.deletionConfirmAccount.trim() != "我确认注销账号" ||
            auth.deletionConfirmDestroy.trim() != "确认销毁" ||
            auth.deletionConfirmWaiveRights.trim() != "确认清理远程连接数据"
        ) {
            auth = auth.copy(message = "请完整输入注销确认文案。")
            return
        }
        viewModelScope.launch {
            auth = auth.copy(submitting = true, message = null)
            runCatching {
                api.deleteAccount(
                    confirmAccount = auth.deletionConfirmAccount,
                    confirmDestroy = auth.deletionConfirmDestroy,
                    confirmWaiveRights = auth.deletionConfirmWaiveRights,
                    reason = auth.deletionReason,
                    accessToken = session.accessToken,
                )
            }
                .onSuccess {
                    auth = auth.copy(submitting = false, message = "账号已注销。")
                    logout()
                    onLoggedOut()
                }
                .onFailure { auth = auth.copy(submitting = false, message = userMessage(it, "账号注销失败。")) }
        }
    }

    fun loadLegalDocuments() {
        viewModelScope.launch {
            val docs = fetchLegalDocuments()
            if (docs.isNotEmpty()) auth = auth.copy(legalDocuments = docs)
        }
    }

    fun presentLegal(type: String) {
        val cached = auth.legalDocuments[type]
        if (cached != null) {
            auth = auth.copy(selectedLegalDocument = cached)
            return
        }
        viewModelScope.launch {
            val docs = fetchLegalDocuments()
            val document = docs[type]
            auth = auth.copy(
                legalDocuments = if (docs.isNotEmpty()) docs else auth.legalDocuments,
                selectedLegalDocument = document,
                message = if (document == null) "协议文档暂时无法打开，请稍后重试。" else auth.message,
            )
        }
    }

    fun dismissLegal() {
        auth = auth.copy(selectedLegalDocument = null)
    }

    fun loadRemoteDevices() {
        val session = sessionStore.load() ?: return
        viewModelScope.launch {
            devices = devices.copy(loading = true, message = null)
            runCatching {
                val listed = api.devices(session.accessToken).filter { it.deviceType == "desktop" || it.platform == "macos" }
                enrichDesktopDevices(listed, session.accessToken)
            }
                .onSuccess { devices = devices.copy(devices = it, loading = false) }
                .onFailure { devices = devices.copy(loading = false, message = userMessage(it, "设备列表加载失败。")) }
        }
    }

    private suspend fun enrichDesktopDevices(
        devices: List<RemoteDeviceInfo>,
        accessToken: String,
    ): List<RemoteDeviceInfo> =
        devices.map { device ->
            if (device.hasDirectEndpoint() || !device.canRequestConnection()) {
                device
            } else {
                runCatching { api.device(device.id, accessToken) }.getOrDefault(device)
            }
        }

    fun updateDeviceCode(value: String) {
        devices = devices.copy(deviceCode = value, message = null)
    }

    fun resolveDeviceCode() {
        val session = sessionStore.load() ?: return
        val code = devices.deviceCode.trim()
        if (code.isBlank()) {
            devices = devices.copy(message = "请输入设备码。")
            return
        }
        viewModelScope.launch {
            devices = devices.copy(resolvingCode = true, message = null)
            runCatching {
                val registeredIdentity = ensureRegisteredLocalDevice(session.accessToken, startSignaling = true)
                api.resolveDeviceCode(code, registeredIdentity, session.accessToken)
            }
                .onSuccess { devices = devices.copy(resolvingCode = false, resolvedDevice = it, message = "已找到 ${it.deviceName}。") }
                .onFailure { devices = devices.copy(resolvingCode = false, resolvedDevice = null, message = userMessage(it, "设备码解析失败。")) }
        }
    }

    fun connectRemoteDevice(device: RemoteDeviceInfo, onConnected: () -> Unit) {
        val session = sessionStore.load() ?: return
        if (devices.connecting) return
        if (!device.remoteEnabled || device.status.lowercase() != "active") {
            devices = devices.copy(message = "这台电脑暂未开启远程连接。")
            return
        }
        if (!device.online) {
            devices = devices.copy(message = "这台电脑当前离线，无法发起连接。")
            return
        }
        viewModelScope.launch {
            devices = devices.copy(connecting = true, message = null)
            snapshot = null
            chat = ChatUiState(connectionStatus = "连接中")
            runCatching {
                remoteChatClient.disconnect()
                remoteWebRtcTransport?.disconnect()
                remoteWebRtcTransport = null
                remoteTunnelTransport?.disconnect()
                remoteTunnelTransport = null
                signalingClient.onRelay = null

                val identity = ensureRegisteredLocalDevice(session.accessToken, startSignaling = true)
                var latestDevice = runCatching { api.device(device.id, session.accessToken) }.getOrDefault(device)
                if (LanNetworkSelector.isOnWifi(getApplication())) {
                    directChatConfigFromDevice(latestDevice, transport = "lan")
                        ?.takeIf { it.isPrivateLanConfig() }
                        ?.let { config ->
                            devices = devices.copy(message = "正在建立局域网直连。")
                            if (tryEstablishDirectConnection(config) == null && isRemoteChatReady()) {
                                devices = devices.copy(
                                    connecting = false,
                                    connectedDeviceId = latestDevice.id,
                                    connectedDeviceName = latestDevice.deviceName,
                                    connectedTransport = "lan",
                                )
                                onConnected()
                                return@launch
                            }
                        }
                }
                val initial = api.connect(latestDevice.id, identity, session.accessToken)
                val attempt =
                    if (initial.status == "pending") waitForConnectionDecision(initial.connectionId ?: initial.id, session.accessToken) else initial
                if (attempt.status != "accepted") {
                    devices = devices.copy(
                        connecting = false,
                        message = attempt.reason ?: when (attempt.status) {
                            "pending" -> "连接请求已发送，请在电脑端允许。"
                            "rejected" -> "电脑端已拒绝连接。"
                            "expired" -> "连接请求已过期，请重新发起连接。"
                            else -> "连接请求未完成：${attempt.status}"
                        },
                    )
                    return@runCatching
                }

                latestDevice = runCatching { api.device(device.id, session.accessToken) }.getOrDefault(latestDevice)

                val connectionId = attempt.connectionId ?: attempt.id
                latestDevice = runCatching { api.device(latestDevice.id, session.accessToken) }.getOrDefault(latestDevice)
                var lanFailure: Throwable? = null
                val triedDirectConfigs = mutableListOf<RemoteChatConfig>()

                suspend fun tryDirectCandidate(config: RemoteChatConfig): Boolean {
                    if (triedDirectConfigs.any { config.matchesEndpoint(it) }) return isRemoteChatReady()
                    triedDirectConfigs += config
                    val failure = tryEstablishDirectConnection(config)
                    if (failure != null && config.transport == "lan" && lanFailure == null) {
                        lanFailure = failure
                    }
                    return failure == null && isRemoteChatReady()
                }

                if (!isRemoteChatReady() && LanNetworkSelector.isOnWifi(getApplication())) {
                    val targetDeviceId = attempt.toDeviceId ?: latestDevice.id
                    val signalingLan = runCatching {
                        waitForSignalingReady()
                        LanSignalingResolver.resolve(
                            connectionId = connectionId,
                            targetDeviceId = targetDeviceId,
                            signalingClient = signalingClient,
                        )
                    }.getOrNull()?.copy(
                        connectionId = connectionId,
                        remoteAccessToken = session.accessToken,
                        reason = attempt.reason,
                    )
                    signalingLan
                        ?.takeIf { it.isPrivateLanConfig() }
                        ?.let { config ->
                            devices = devices.copy(message = "正在建立局域网直连。")
                            tryDirectCandidate(config)
                        }
                }

                if (!isRemoteChatReady()) {
                    directChatConfigFromAttempt(attempt, session.accessToken, transport = "lan")
                        ?.takeIf { it.isPrivateLanConfig() }
                        ?.let { config ->
                            devices = devices.copy(message = "正在建立局域网直连。")
                            tryDirectCandidate(config)
                        }
                }

                if (!isRemoteChatReady()) {
                    directChatConfigFromDevice(latestDevice, attempt, session.accessToken, transport = "lan")
                        ?.takeIf { it.isPrivateLanConfig() }
                        ?.let { config ->
                            devices = devices.copy(message = "正在建立局域网直连。")
                            tryDirectCandidate(config)
                        }
                }

                var crossNetworkFailure: Throwable? = null
                if (!isRemoteChatReady()) {
                    runCatching {
                        connectRemoteTunnel(attempt, session.accessToken)
                    }.onFailure { tunnelError ->
                        crossNetworkFailure = tunnelError
                        runCatching {
                            connectRemoteRelay(attempt, latestDevice, session.accessToken)
                        }.onFailure { relayError ->
                            crossNetworkFailure = relayError
                        }
                    }
                }

                if (!isRemoteChatReady()) {
                    val publicCandidates = listOfNotNull(
                        directChatConfigFromAttempt(attempt, session.accessToken, transport = "public"),
                        directChatConfigFromDevice(latestDevice, attempt, session.accessToken, transport = "public"),
                    ).filter { it.isPublicDirectConfig() }
                    for (config in publicCandidates) {
                        devices = devices.copy(message = "正在尝试公网端口直连。")
                        if (tryDirectCandidate(config)) break
                    }
                    if (!isRemoteChatReady() && crossNetworkFailure != null && publicCandidates.isEmpty()) {
                        throw crossNetworkFailure!!
                    }
                }

                if (isRemoteChatReady()) {
                    val fallbackNote = lanFallbackNote(
                        transport = chat.config.transport,
                        lanFailure = lanFailure,
                    )
                    devices = devices.copy(
                        connecting = false,
                        connectedDeviceId = latestDevice.id,
                        connectedDeviceName = latestDevice.deviceName,
                        connectedTransport = chat.config.transport,
                        message = fallbackNote,
                    )
                    onConnected()
                } else {
                    devices = devices.copy(
                        connecting = false,
                        message = "连接已允许，但暂时拿不到电脑的连接地址。请确认手机与电脑在同一 WiFi 后刷新设备列表重试。",
                    )
                }
            }.onFailure {
                devices = devices.copy(
                    connecting = false,
                    message = connectionFailureMessage(it, latestDevice = runCatching {
                        val session = sessionStore.load() ?: return@runCatching null
                        api.device(device.id, session.accessToken)
                    }.getOrNull()),
                )
            }
        }
    }

    fun connectResolvedDevice(onConnected: () -> Unit) {
        val resolved = devices.resolvedDevice ?: return
        connectRemoteDevice(
            RemoteDeviceInfo(
                id = resolved.deviceId,
                userId = null,
                deviceUid = null,
                deviceName = resolved.deviceName,
                deviceType = "desktop",
                platform = resolved.platform,
                approvalPolicy = resolved.approvalPolicy,
                remoteEnabled = true,
                status = "active",
                online = true,
                lastSeenAt = null,
                lanEndpoint = null,
                transientToken = null,
            ),
            onConnected,
        )
    }

    fun refreshChat() {
        val config = chat.config
        if (!config.isComplete) {
            chat = chat.copy(connectionStatus = "未连接", lastError = "请先连接远程设备。")
            return
        }
        viewModelScope.launch {
            chat = chat.copy(isRefreshing = true, lastError = null)
            if (config.supportsDirectHttp) {
                val healthOk = runCatching { RemoteLanClient(config, lanBoundClient()).health() }.getOrDefault(false)
                if (!healthOk || chat.connectionStatus != "已连接") connectRemoteChat(config)
                sendRemoteCommand("requestSnapshot", sessionId = chat.selectedSessionId)
            } else {
                sendRemoteCommand("requestSnapshot", sessionId = chat.selectedSessionId)
            }
            waitForSnapshotRevisionAfter(snapshot?.revision ?: 0)
            if (config.supportsDirectHttp) reloadFiles()
            chat = chat.copy(isRefreshing = false)
        }
    }

    fun resumeFromForeground() {
        if (auth.gateState == AuthGateState.Authenticated && chat.config.isComplete) {
            refreshChat()
        }
    }

    fun selectProject(project: RemoteProject) {
        chat = chat.copy(
            selectedProjectId = project.id,
            selectedSessionId = null,
            inputText = "",
            attachments = emptyList(),
            files = emptyList(),
            fileError = null,
        )
        scheduleProjectFocusTimeout(project.id)
        sendRemoteCommand("focusProject", args = JSONObject().put("projectId", project.id))
        viewModelScope.launch { reloadFiles() }
    }

    fun selectModel(model: RemoteModel) {
        chat = chat.copy(selectedModelId = model.id, composer = chat.composer.copy(modelID = model.id))
        sendRemoteCommand(
            "composerSetModel",
            sessionId = chat.selectedSessionId,
            args = expectedArgs().put("modelID", model.id),
        )
    }

    fun setCLI(cli: String) {
        val next = cli.trim().lowercase()
        if (next.isBlank()) return
        chat = chat.copy(composer = chat.composer.copy(cli = next))
        sendRemoteCommand(
            "composerSetCLI",
            sessionId = chat.selectedSessionId,
            args = expectedArgs().put("cli", next),
        )
    }

    fun setPermissionMode(permissionMode: String) {
        val next = permissionMode.trim()
        if (next.isBlank()) return
        chat = chat.copy(composer = chat.composer.copy(permissionMode = next))
        sendRemoteCommand(
            "composerSetPermissionMode",
            sessionId = chat.selectedSessionId,
            args = expectedArgs().put("permissionMode", next),
        )
    }

    fun setReasoningEffort(reasoningEffort: String) {
        val next = reasoningEffort.trim()
        if (next.isBlank()) return
        chat = chat.copy(composer = chat.composer.copy(reasoningEffort = next))
        sendRemoteCommand(
            "composerSetReasoningEffort",
            sessionId = chat.selectedSessionId,
            args = expectedArgs().put("reasoningEffort", next),
        )
    }

    fun selectSession(session: RemoteSession) {
        chat = chat.copy(
            selectedSessionId = session.id,
            selectedProjectId = session.projectId ?: chat.selectedProjectId,
            inputText = "",
            attachments = emptyList(),
        )
        scheduleSessionFocusTimeout(session.id)
        sendRemoteCommand("focusSession", sessionId = session.id, args = JSONObject().put("sessionId", session.id))
    }

    fun startNewChat() {
        val projectId = chat.selectedProject?.id ?: return
        chat = chat.copy(selectedSessionId = null, inputText = "", attachments = emptyList(), messages = emptyList())
        sendRemoteCommand("focusProject", args = JSONObject().put("projectId", projectId))
        sendRemoteCommand("newDraftSession", args = JSONObject().put("projectId", projectId))
    }

    fun updateInput(value: String) {
        chat = chat.copy(inputText = value)
    }

    fun sendCurrentMessage() {
        val text = chat.inputText.trim()
        val attachments = chat.attachments
        if (text.isBlank() && attachments.isEmpty()) return
        val expected = expectedArgs()
        attachments.forEach { attachment ->
            sendRemoteCommand(
                "composerAttach",
                sessionId = chat.selectedSessionId,
                args = JSONObject(expected.toString()).put("attachment", attachment.toJson()),
            )
        }
        sendRemoteCommand("composerSet", sessionId = chat.selectedSessionId, args = JSONObject(expected.toString()).put("text", text))
        sendRemoteCommand("composerSend", sessionId = chat.selectedSessionId, args = expected)
        val optimistic = com.codevoke.android.data.RemoteChatMessage(kind = "user", text = text, status = "queued", attachments = attachments)
        chat = chat.copy(inputText = "", attachments = emptyList(), messages = chat.messages + optimistic)
    }

    fun uploadAttachment(filename: String, data: ByteArray, kind: String, thumbnailData: String?) {
        val safeName = filename.trim().ifBlank { if (kind == "image") "image.jpg" else "attachment" }
        val attachmentKind = kind.ifBlank { "file" }
        if (data.isEmpty()) {
            chat = chat.copy(lastError = "附件为空，无法上传。")
            return
        }
        if (!chat.config.supportsDirectHttp) {
            chat = chat.copy(lastError = "远程连接暂不支持附件上传，请在同一局域网连接后使用。")
            return
        }
        if (data.size > maxAttachmentBytes) {
            chat = chat.copy(lastError = "单个附件不能超过 10MB。")
            return
        }
        val totalSize = chat.attachments.sumOf { it.sizeBytes } + data.size
        if (totalSize > maxTotalAttachmentBytes) {
            chat = chat.copy(lastError = "本次消息附件总大小不能超过 20MB。")
            return
        }
        val config = chat.config
        val selectedProjectId = chat.selectedProjectId
        val selectedSessionId = chat.selectedSessionId
        viewModelScope.launch {
            beginAttachmentUpload()
            runCatching { RemoteLanClient(config).uploadAttachment(safeName, data) }
                .onSuccess { uploaded ->
                    if (chat.selectedProjectId != selectedProjectId || chat.selectedSessionId != selectedSessionId) {
                        finishAttachmentUpload()
                        return@onSuccess
                    }
                    val attachment = RemoteChatAttachment(
                        kind = attachmentKind,
                        filename = uploaded.filename.ifBlank { safeName },
                        path = uploaded.path,
                        thumbnailData = thumbnailData,
                        sizeBytes = data.size,
                    )
                    chat = chat.copy(
                        attachments = chat.attachments + attachment,
                    )
                    finishAttachmentUpload()
                }
                .onFailure {
                    finishAttachmentUpload()
                    chat = chat.copy(lastError = userMessage(it, "附件上传失败。"))
                }
        }
    }

    fun removeAttachment(attachmentId: String) {
        chat = chat.copy(attachments = chat.attachments.filterNot { it.id == attachmentId })
    }

    fun stopGeneration() {
        sendRemoteCommand("stop", sessionId = chat.selectedSessionId, args = JSONObject().put("startQueuedAfterStop", false))
    }

    fun cancelQueued(requestId: String) {
        val id = requestId.trim()
        if (id.isBlank()) return
        sendRemoteCommand(
            "cancelQueued",
            sessionId = chat.selectedSessionId,
            args = expectedArgs().put("requestId", id),
        )
    }

    fun flushQueue() {
        sendRemoteCommand("flushQueue", sessionId = chat.selectedSessionId, args = expectedArgs())
    }

    fun editQueued(requestId: String, text: String) {
        val id = requestId.trim()
        val nextText = text.trim()
        if (id.isBlank() || nextText.isBlank()) return
        sendRemoteCommand(
            "editQueued",
            sessionId = chat.selectedSessionId,
            args = expectedArgs()
                .put("requestId", id)
                .put("text", nextText),
        )
    }

    fun respondPermission(requestId: String, decision: String) {
        val id = requestId.trim()
        val nextDecision = decision.trim()
        if (id.isBlank() || nextDecision.isBlank()) return
        sendRemoteCommand(
            "respondPermission",
            sessionId = chat.selectedSessionId,
            args = expectedArgs()
                .put("permissionRequestId", id)
                .put("decision", nextDecision),
        )
    }

    fun respondInteractive(response: RemoteInteractiveResponse) {
        if (response.requestID.isBlank()) return
        sendRemoteCommand(
            "respondInteractive",
            sessionId = chat.selectedSessionId,
            args = expectedArgs()
                .put("interactiveRequestId", response.requestID)
                .put("interactiveResponse", response.toJson()),
        )
    }

    fun respondInteractive(
        requestId: String,
        selectedOptionIds: List<String> = emptyList(),
        customText: String? = null,
    ) {
        respondInteractive(
            RemoteInteractiveResponse(
                requestID = requestId,
                selectedOptionIDs = selectedOptionIds,
                customText = customText,
            ),
        )
    }

    fun requestSnapshot(sessionId: String? = chat.selectedSessionId) {
        sendRemoteCommand("requestSnapshot", sessionId = sessionId)
    }

    fun insertPath(path: String) {
        val next = if (chat.inputText.isBlank()) path else "${chat.inputText}\n$path"
        chat = chat.copy(inputText = next)
    }

    fun openFile(entry: RemoteFileEntry) {
        if (!entry.isDirectory) return
        viewModelScope.launch { reloadFiles(entry.relativePath) }
    }

    fun openParentDirectory() {
        val parent = chat.parentFilePath ?: return
        viewModelScope.launch { reloadFiles(parent) }
    }

    private fun connectRemoteChat(config: RemoteChatConfig, client: OkHttpClient? = null) {
        remoteWebRtcTransport?.disconnect()
        remoteWebRtcTransport = null
        signalingClient.onRelay = null
        currentConnectStartedAtMs = System.currentTimeMillis()
        didReportFirstPanelStateLatency = false
        chat = chat.copy(config = config, connectionStatus = "连接中", lastError = null)
        val lanClient = if (config.isPrivateLanConfig()) {
            LanNetworkSelector.wifiBoundClient(getApplication()) ?: client
        } else {
            client
        }
        remoteChatClient.connect(
            config = config,
            focusedSessionId = chat.selectedSessionId,
            lastRevision = snapshot?.revision,
            client = lanClient,
        )
    }

    private suspend fun connectRemoteRelay(
        attempt: RemoteConnectionAttempt,
        device: RemoteDeviceInfo,
        accessToken: String,
    ) {
        val connectionId = attempt.connectionId ?: attempt.id
        waitForSignalingReady()
        val ice = api.iceServers(connectionId, accessToken)
        val targetDeviceId = attempt.toDeviceId
            ?: throw IllegalStateException("连接信息不完整，请重新发起连接。")
        val transport = RemoteWebRtcTransport(
            context = getApplication(),
            connectionId = connectionId,
            targetDeviceId = targetDeviceId,
            signalingClient = signalingClient,
            iceServers = ice.iceServers,
        )
        bindWebRtcTransport(transport)
        remoteChatClient.disconnect()
        remoteWebRtcTransport?.disconnect()
        remoteWebRtcTransport = transport
        remoteTunnelTransport?.disconnect()
        remoteTunnelTransport = null
        signalingClient.onRelay = { relayConnectionId, payload ->
            if (relayConnectionId == connectionId) transport.receiveRelayPayload(payload)
        }
        val config = RemoteChatConfig(
            macHost = "",
            port = 0,
            token = accessToken,
            connectionId = connectionId,
            transport = attempt.transport ?: "p2p",
            reason = attempt.reason,
            remoteAccessToken = accessToken,
            remoteRelayReady = signalingClient.isConnected,
        )
        currentConnectStartedAtMs = System.currentTimeMillis()
        didReportFirstPanelStateLatency = false
        chat = chat.copy(config = config, connectionStatus = "连接中", lastError = null)
        devices = devices.copy(message = "正在建立远程连接。")
        transport.connect(focusedSessionId = chat.selectedSessionId, lastRevision = snapshot?.revision)
        try {
            waitForRemoteTransportReady(transport)
        } catch (error: Throwable) {
            if (remoteWebRtcTransport === transport) remoteWebRtcTransport = null
            signalingClient.onRelay = null
            chat = chat.copy(connectionStatus = "未连接", lastError = error.localizedMessage)
            throw error
        }
    }

    private suspend fun connectRemoteTunnel(
        attempt: RemoteConnectionAttempt,
        accessToken: String,
    ) {
        val connectionId = attempt.connectionId ?: attempt.id
        waitForSignalingReady()
        val targetDeviceId = attempt.toDeviceId
            ?: throw IllegalStateException("连接信息不完整，请重新发起连接。")
        val transport = RemoteTunnelTransport(
            connectionId = connectionId,
            targetDeviceId = targetDeviceId,
            signalingClient = signalingClient,
        )
        bindTunnelTransport(transport)
        remoteChatClient.disconnect()
        remoteWebRtcTransport?.disconnect()
        remoteWebRtcTransport = null
        remoteTunnelTransport?.disconnect()
        remoteTunnelTransport = transport
        val config = RemoteChatConfig(
            macHost = "",
            port = 0,
            token = accessToken,
            connectionId = connectionId,
            transport = "tunnel",
            reason = attempt.reason,
            remoteAccessToken = accessToken,
            remoteRelayReady = signalingClient.isConnected,
        )
        currentConnectStartedAtMs = System.currentTimeMillis()
        didReportFirstPanelStateLatency = false
        chat = chat.copy(config = config, connectionStatus = "连接中", lastError = null)
        devices = devices.copy(message = "正在建立远程通道。")
        transport.connect(focusedSessionId = chat.selectedSessionId, lastRevision = snapshot?.revision)
        try {
            waitForTunnelReady(transport)
        } catch (error: Throwable) {
            if (remoteTunnelTransport === transport) remoteTunnelTransport = null
            chat = chat.copy(connectionStatus = "未连接", lastError = error.localizedMessage)
            throw error
        }
    }

    private fun bindTunnelTransport(transport: RemoteTunnelTransport) {
        transport.onStatus = { status ->
            viewModelScope.launch {
                chat = chat.copy(connectionStatus = status)
                if (status == "已连接") replayPendingCommands()
            }
        }
        transport.onError = { error -> viewModelScope.launch { chat = chat.copy(lastError = error) } }
        transport.onSnapshot = { next -> viewModelScope.launch { adoptSnapshot(next) } }
        transport.onPatch = { patch -> viewModelScope.launch { applyRemotePatch(patch) } }
        transport.onAck = { commandId, status, message, sessionId ->
            viewModelScope.launch {
                removePendingCommand(commandId)
                if (!sessionId.isNullOrBlank()) chat = chat.copy(selectedSessionId = sessionId)
                if (status == "error" || status == "rejected") chat = chat.copy(lastError = message)
            }
        }
    }

    private suspend fun waitForTunnelReady(transport: RemoteTunnelTransport) {
        repeat(240) {
            if (transport.isReady || transport.awaitReady(100)) return
            if (!signalingClient.isConnected) throw IllegalStateException("信令通道已断开，请确认网络后重试。")
        }
        transport.disconnect()
        throw IllegalStateException("远程通道建立超时，请确认电脑端在线后重试。")
    }

    private fun bindWebRtcTransport(transport: RemoteWebRtcTransport) {
        transport.onStatus = { status ->
            viewModelScope.launch {
                chat = chat.copy(connectionStatus = status)
            if (status == "已连接") replayPendingCommands()
            }
        }
        transport.onError = { error -> viewModelScope.launch { chat = chat.copy(lastError = error) } }
        transport.onSnapshot = { next -> viewModelScope.launch { adoptSnapshot(next) } }
        transport.onPatch = { patch -> viewModelScope.launch { applyRemotePatch(patch) } }
        transport.onAck = { commandId, status, message, sessionId ->
            viewModelScope.launch {
                removePendingCommand(commandId)
                if (!sessionId.isNullOrBlank()) chat = chat.copy(selectedSessionId = sessionId)
                if (status == "error" || status == "rejected") chat = chat.copy(lastError = message)
            }
        }
    }

    private fun sendRemoteCommand(op: String, sessionId: String? = null, args: JSONObject = JSONObject()): String {
        val commandId = UUID.randomUUID().toString()
        trackPendingCommand(PendingRemoteCommand(commandId, op, sessionId, JSONObject(args.toString())))
        return sendRemoteCommandInternal(commandId, op, sessionId, args)
    }

    private fun sendRemoteCommandInternal(commandId: String, op: String, sessionId: String? = null, args: JSONObject = JSONObject()): String {
        val tunnel = remoteTunnelTransport
        val relay = remoteWebRtcTransport
        return if (tunnel != null && tunnel.isReady && !chat.config.supportsDirectHttp) {
            tunnel.sendCommand(op, sessionId, args, commandId)
        } else if (relay != null && !chat.config.supportsDirectHttp) {
            relay.sendCommand(op, sessionId, args, commandId)
        } else {
            remoteChatClient.sendCommand(op, sessionId, args, commandId)
        }
    }

    private fun trackPendingCommand(command: PendingRemoteCommand) {
        pendingCommands.removeAll { it.commandId == command.commandId }
        pendingCommands += command
        if (pendingCommands.size > 200) {
            pendingCommands.subList(0, pendingCommands.size - 200).clear()
        }
    }

    private fun removePendingCommand(commandId: String) {
        pendingCommands.removeAll { it.commandId == commandId }
    }

    private fun replayPendingCommands() {
        val commands = pendingCommands.toList()
        commands.forEach { command ->
            sendRemoteCommandInternal(
                commandId = command.commandId,
                op = command.op,
                sessionId = command.sessionId,
                args = JSONObject(command.args.toString()),
            )
        }
    }

    private fun bindChatClient() {
        remoteChatClient.onStatus = { status ->
            viewModelScope.launch {
                chat = chat.copy(connectionStatus = status)
                if (status == "已连接") replayPendingCommands()
            }
        }
        remoteChatClient.onError = { error -> viewModelScope.launch { chat = chat.copy(lastError = error) } }
        remoteChatClient.onSnapshot = { next -> viewModelScope.launch { adoptSnapshot(next) } }
        remoteChatClient.onPatch = { patch -> viewModelScope.launch { applyRemotePatch(patch) } }
        remoteChatClient.onAck = { commandId, status, message, sessionId ->
            viewModelScope.launch {
                removePendingCommand(commandId)
                if (!sessionId.isNullOrBlank()) chat = chat.copy(selectedSessionId = sessionId)
                if (status == "error" || status == "rejected") chat = chat.copy(lastError = message)
            }
        }
    }

    private fun adoptSnapshot(next: RemotePanelSnapshot) {
        snapshot = next
        reportFirstPanelStateLatencyIfNeeded()
        remoteChatClient.updateResumeContext(next.currentSessionId ?: chat.selectedSessionId, next.revision)
        val projectId = chat.selectedProjectId ?: next.sessions.firstOrNull { it.id == next.currentSessionId }?.projectId ?: next.projects.firstOrNull()?.id
        val modelId = next.composer.modelID.ifBlank {
            next.models.firstOrNull { it.cli == next.composer.cli && it.isDefault }?.id ?: next.models.firstOrNull()?.id.orEmpty()
        }
        chat = chat.copy(
            projects = next.projects,
            models = next.models,
            sessions = next.sessions,
            selectedProjectId = projectId,
            selectedSessionId = next.currentSessionId ?: chat.selectedSessionId,
            selectedModelId = modelId,
            messages = next.messages,
            streamingTexts = next.streamingTexts,
            composer = next.composer,
            queuedRequests = next.queuedRequests,
            runtimeStatus = next.statusText.ifBlank { next.status },
            isAwaitingFirstModelOutput = next.isAwaitingFirstModelOutput,
            isLoadingHistory = next.isLoadingHistory,
            tokensUsed = next.tokensUsed,
            tokensTotal = next.tokensTotal,
            lastError = null,
        )
        if (chat.config.supportsDirectHttp) viewModelScope.launch { reloadFiles() }
    }

    private fun applyRemotePatch(patch: com.codevoke.android.data.RemotePanelPatch) {
        val current = snapshot
        if (current == null) {
            requestSnapshot(patch.sessionId ?: chat.selectedSessionId)
            return
        }
        val merged = current.applyPatch(patch)
        if (merged == null) {
            requestSnapshot(patch.sessionId ?: current.currentSessionId ?: chat.selectedSessionId)
            return
        }
        adoptSnapshot(merged)
    }

    private suspend fun reloadFiles(path: String = chat.currentFilePath) {
        val project = chat.selectedProject ?: return
        val config = chat.config
        if (!config.supportsDirectHttp) {
            chat = chat.copy(
                files = emptyList(),
                isLoadingFiles = false,
                fileError = "远程连接暂不支持文件树浏览，请在同一局域网连接后使用。",
            )
            return
        }
        chat = chat.copy(isLoadingFiles = true, fileError = null)
        runCatching { RemoteLanClient(config).projectFiles(project.id, path) }
            .onSuccess {
                chat = chat.copy(
                    files = it.entries,
                    currentFilePath = it.path,
                    parentFilePath = it.parentPath,
                    isLoadingFiles = false,
                    fileError = null,
                )
            }
            .onFailure { chat = chat.copy(isLoadingFiles = false, fileError = userMessage(it, "文件列表加载失败。")) }
    }

    private fun beginAttachmentUpload() {
        pendingAttachmentUploadCount += 1
        chat = chat.copy(isUploadingAttachment = true, lastError = null)
    }

    private fun finishAttachmentUpload() {
        pendingAttachmentUploadCount = (pendingAttachmentUploadCount - 1).coerceAtLeast(0)
        chat = chat.copy(isUploadingAttachment = pendingAttachmentUploadCount > 0)
    }

    private fun reportFirstPanelStateLatencyIfNeeded() {
        if (didReportFirstPanelStateLatency) return
        val startedAt = currentConnectStartedAtMs ?: return
        val connectionId = chat.config.connectionId ?: return
        val accessToken = chat.config.remoteAccessToken ?: return
        didReportFirstPanelStateLatency = true
        val latency = (System.currentTimeMillis() - startedAt).coerceAtLeast(0).toInt()
        val transport = chat.config.transport ?: if (chat.config.supportsDirectHttp) "lan" else "p2p"
        val path = when (transport) {
            "lan" -> "lan"
            "public", "port_forward" -> "public"
            "tunnel" -> "tunnel"
            else -> "relay"
        }
        viewModelScope.launch {
            runCatching {
                api.reportConnectionMetrics(
                    connectionId = connectionId,
                    request = RemoteConnectionMetricsRequest(
                        transport = transport,
                        firstPacketLatencyMs = latency,
                        stage = "first_panel_state",
                        path = path,
                    ),
                    accessToken = accessToken,
                )
            }
        }
    }

    private suspend fun registerLocalDevice(accessToken: String) {
        ensureRegisteredLocalDevice(accessToken, startSignaling = true)
    }

    private suspend fun ensureRegisteredLocalDevice(accessToken: String, startSignaling: Boolean): LocalDeviceIdentity {
        val identity = identityStore.identity()
        val cachedDevice = identity.deviceId
            ?.let { deviceId -> runCatching { api.device(deviceId, accessToken) }.getOrNull() }
            ?.takeIf { it.matchesLocalIdentity(identity) }
        val device = cachedDevice
            ?: runCatching { api.devices(accessToken).firstOrNull { it.matchesLocalIdentity(identity) } }.getOrNull()
            ?: api.registerDevice(identity, accessToken)
        if (identity.deviceId != device.id) {
            identityStore.updateDeviceId(device.id)
        }
        if (startSignaling) {
            signalingClient.start(accessToken, device.id)
        }
        return identityStore.identity()
    }

    private fun RemoteDeviceInfo.matchesLocalIdentity(identity: LocalDeviceIdentity): Boolean {
        val type = deviceType?.lowercase().orEmpty()
        val currentPlatform = platform?.lowercase().orEmpty()
        return deviceUid == identity.deviceUid && (type == "android" || currentPlatform == "android")
    }

    private suspend fun submitLegalConsents(accessToken: String) {
        val deviceId = identityStore.identity().deviceId ?: return
        val documents = auth.legalDocuments.ifEmpty {
            val docs = fetchLegalDocuments()
            if (docs.isNotEmpty()) auth = auth.copy(legalDocuments = docs)
            docs
        }
        documents.values.forEach { document ->
            runCatching { api.consent(document.id, deviceId, accessToken) }
        }
    }

    private suspend fun fetchLegalDocuments(): Map<String, RemoteLegalDocument> {
        val docs = mutableMapOf<String, RemoteLegalDocument>()
        runCatching { api.legalDocument("privacy_policy") }.onSuccess { docs["privacy_policy"] = it }
        runCatching { api.legalDocument("user_agreement") }.onSuccess { docs["user_agreement"] = it }
        return docs
    }

    private fun startRegisterCodeCooldown(seconds: Int = 60) {
        registerCodeCooldownJob?.cancel()
        registerCodeCooldownJob = viewModelScope.launch {
            for (remaining in seconds downTo 1) {
                auth = auth.copy(registerCodeCooldown = remaining)
                delay(1_000)
            }
            auth = auth.copy(registerCodeCooldown = 0)
        }
    }

    private fun startPasswordResetCodeCooldown(seconds: Int = 60) {
        passwordResetCodeCooldownJob?.cancel()
        passwordResetCodeCooldownJob = viewModelScope.launch {
            for (remaining in seconds downTo 1) {
                auth = auth.copy(passwordResetCodeCooldown = remaining)
                delay(1_000)
            }
            auth = auth.copy(passwordResetCodeCooldown = 0)
        }
    }

    private fun expectedArgs(): JSONObject {
        val args = JSONObject()
        chat.selectedProjectId?.let { args.put("expectedProjectId", it) }
        chat.selectedSessionId?.let { args.put("expectedSessionId", it) }
        return args
    }

    private fun RemoteInteractiveResponse.toJson(): JSONObject {
        val selected = org.json.JSONArray()
        selectedOptionIDs.forEach { selected.put(it) }
        return JSONObject()
            .put("requestID", requestID)
            .put("selectedOptionIDs", selected)
            .put("customText", customText)
    }

    private fun scheduleProjectFocusTimeout(projectId: String) {
        pendingProjectFocusJob?.cancel()
        pendingProjectFocusJob = viewModelScope.launch {
            delay(8_000)
            if (chat.selectedProjectId == projectId) {
                sendRemoteCommand("requestSnapshot", sessionId = chat.selectedSessionId)
            }
        }
    }

    private fun scheduleSessionFocusTimeout(sessionId: String) {
        pendingSessionFocusJob?.cancel()
        pendingSessionFocusJob = viewModelScope.launch {
            delay(8_000)
            if (chat.selectedSessionId == sessionId) {
                sendRemoteCommand("requestSnapshot", sessionId = sessionId)
            }
        }
    }

    private suspend fun waitForConnectionDecision(connectionId: Int, accessToken: String): RemoteConnectionAttempt {
        devices = devices.copy(message = "连接请求已发送，请在电脑端允许。")
        bufferedDecisions.remove(connectionId)?.let { return it }
        val delays = listOf(2_000L, 3_000L, 5_000L, 8_000L, 10_000L, 10_000L, 10_000L, 10_000L)
        for (delayMs in delays) {
            delay(delayMs)
            bufferedDecisions.remove(connectionId)?.let { return it }
            val connection = runCatching { api.connection(connectionId, accessToken) }.getOrNull()
            if (connection != null && connection.status != "pending") return connection
        }
        throw IllegalStateException("等待电脑端确认超时，请确认设备在线后重试。")
    }

    private suspend fun waitForSignalingReady() {
        repeat(80) {
            if (signalingClient.isConnected) return
            delay(100)
        }
        throw IllegalStateException("信令通道连接超时，请确认网络后重试。")
    }

    private suspend fun waitForRemoteTransportReady(transport: RemoteWebRtcTransport) {
        repeat(240) {
            if (transport.isReady || transport.awaitReady(100)) return
            if (!signalingClient.isConnected) throw IllegalStateException("信令通道已断开，请确认网络后重试。")
        }
        transport.disconnect()
        throw IllegalStateException("远程连接通道建立超时，请确认电脑端在线后重试。")
    }

    private suspend fun waitForDirectRemoteChatReady() {
        repeat(160) {
            if (remoteChatClient.isReady || remoteChatClient.awaitReady(100)) return
        }
        remoteChatClient.disconnect()
        chat = chat.copy(connectionStatus = "未连接", lastError = "局域网连接通道建立超时，请确认电脑端在线后重试。")
        throw IllegalStateException("局域网连接通道建立超时，请确认电脑端在线后重试。")
    }

    private suspend fun waitForSnapshotRevisionAfter(previousRevision: Int) {
        repeat(30) {
            if ((snapshot?.revision ?: 0) > previousRevision) return
            delay(100)
        }
    }

    private fun bindSignalingClient() {
        signalingClient.onPresenceUpdate = { deviceId, online ->
            viewModelScope.launch {
                devices = devices.copy(devices = devices.devices.map { if (it.id == deviceId) it.copy(online = online) else it })
            }
        }
        signalingClient.onConnectDecision = { connection ->
            viewModelScope.launch {
                val id = connection.connectionId ?: connection.id
                bufferedDecisions[id] = connection
                if (bufferedDecisions.size > 20) bufferedDecisions.clear()
            }
        }
    }

    private fun userMessage(error: Throwable, fallback: String = "请求失败。"): String {
        return error.localizedMessage?.takeIf { it.isNotBlank() } ?: fallback
    }

    private fun connectionFailureMessage(error: Throwable, latestDevice: RemoteDeviceInfo?): String {
        val base = userMessage(error, "连接请求失败。")
        val lacksLanEndpoint = latestDevice?.lanEndpoint == null || latestDevice.transientToken.isNullOrBlank()
        return if (lacksLanEndpoint && base.contains("远程连接没有建立成功")) {
            "局域网直连失败，请确认手机与电脑在同一 WiFi，且 Mac 端已开启「允许局域网直连」。若仍走跨网，请重启 Mac 端 App 后重试。"
        } else {
            base
        }
    }

    private fun lanFallbackNote(transport: String?, lanFailure: Throwable?): String? {
        if (transport != "tunnel" || lanFailure == null) return null
        val onWifi = LanNetworkSelector.wifiNetwork(getApplication()) != null
        val detail = userMessage(lanFailure, "无法直连电脑")
        return if (onWifi) {
            "已改用跨网通道（局域网不可用：$detail）。若在同一 WiFi 仍失败，请检查路由器是否开启「AP 隔离」，或改用 Mac 热点。"
        } else {
            "已改用跨网通道（当前未连 WiFi，无法局域网直连：$detail）。"
        }
    }

    private fun isRemoteChatReady(): Boolean =
        chat.connectionStatus == "已连接" || remoteChatClient.isReady || remoteWebRtcTransport?.isReady == true || remoteTunnelTransport?.isReady == true

    private fun directChatConfigFromAttempt(
        attempt: RemoteConnectionAttempt,
        accessToken: String,
        transport: String,
    ): RemoteChatConfig? {
        val endpoint = attempt.endpoint ?: return null
        val token = attempt.transientToken?.trim().orEmpty()
        if (token.isBlank()) return null
        return RemoteChatConfig(
            macHost = endpoint.ip,
            port = endpoint.port,
            token = token,
            connectionId = attempt.connectionId ?: attempt.id,
            transport = transport,
            reason = attempt.reason,
            remoteAccessToken = accessToken,
        )
    }

    private fun directChatConfigFromDevice(
        device: RemoteDeviceInfo,
        transport: String,
    ): RemoteChatConfig? {
        val endpoint = device.lanEndpoint ?: return null
        val token = device.transientToken?.trim().orEmpty()
        if (token.isBlank()) return null
        return RemoteChatConfig(
            macHost = endpoint.ip,
            port = endpoint.port,
            token = token,
            connectionId = null,
            transport = transport,
        )
    }

    private fun directChatConfigFromDevice(
        device: RemoteDeviceInfo,
        attempt: RemoteConnectionAttempt,
        accessToken: String,
        transport: String,
    ): RemoteChatConfig? {
        val endpoint = device.lanEndpoint ?: return null
        val token = device.transientToken?.trim().orEmpty()
        if (token.isBlank()) return null
        return RemoteChatConfig(
            macHost = endpoint.ip,
            port = endpoint.port,
            token = token,
            connectionId = attempt.connectionId ?: attempt.id,
            transport = transport,
            reason = attempt.reason,
            remoteAccessToken = accessToken,
        )
    }

    private fun RemoteChatConfig.matchesEndpoint(other: RemoteChatConfig?): Boolean {
        if (other == null) return false
        return macHost == other.macHost && port == other.port && token == other.token
    }

    private fun RemoteChatConfig.isPrivateLanConfig(): Boolean =
        supportsDirectHttp && isPrivateIPv4Host(macHost)

    private fun RemoteChatConfig.isPublicDirectConfig(): Boolean =
        supportsDirectHttp && !isPrivateLanConfig()

    private fun isPrivateIPv4Host(host: String): Boolean {
        val octets = host.trim().split(".").mapNotNull { it.toIntOrNull() }
        if (octets.size != 4 || octets.any { it !in 0..255 }) return false
        return when (octets[0]) {
            10 -> true
            172 -> octets[1] in 16..31
            192 -> octets[1] == 168
            else -> false
        }
    }

    private suspend fun tryEstablishDirectConnection(config: RemoteChatConfig): Throwable? {
        val app = getApplication<Application>()
        var directConfig = config.copy(
            transport = "lan",
            connectionId = null,
        )
        val clients = LanNetworkSelector.lanClientsForAttempt(app)
        val wifiSubnet = LanNetworkSelector.wifiSubnetPrefix(app)
        val offeredSubnet = directConfig.macHost.split(".").take(3).joinToString(".")
        if (
            wifiSubnet != null &&
            directConfig.isPrivateLanConfig() &&
            offeredSubnet != wifiSubnet
        ) {
            LanSubnetProbe.discoverHealthHost(
                context = app,
                port = directConfig.port,
                preferredHost = LanNetworkSelector.localWifiIPv4(app),
            )?.let { discoveredHost ->
                directConfig = directConfig.copy(macHost = discoveredHost)
            }
        }

        var healthClient: OkHttpClient? = null
        for (client in clients) {
            if (runCatching { RemoteLanClient(directConfig, client).health() }.getOrDefault(false)) {
                healthClient = client
                break
            }
        }
        if (healthClient == null && directConfig.isPrivateLanConfig()) {
            val discoveredHost = LanSubnetProbe.discoverHealthHost(
                context = app,
                port = directConfig.port,
                preferredHost = directConfig.macHost,
            )
            if (discoveredHost != null) {
                directConfig = directConfig.copy(macHost = discoveredHost)
                for (client in clients) {
                    if (runCatching { RemoteLanClient(directConfig, client).health() }.getOrDefault(false)) {
                        healthClient = client
                        break
                    }
                }
            }
        }
        if (healthClient == null) {
            val failure = IllegalStateException(
                "无法访问电脑地址 ${directConfig.macHost}:${directConfig.port}，请确认手机与电脑在同一 WiFi。",
            )
            chat = chat.copy(connectionStatus = "未连接", lastError = failure.localizedMessage)
            return failure
        }

        val wsClients = buildList {
            add(healthClient)
            addAll(clients.filter { it !== healthClient })
        }
        var lastError: Throwable? = null
        for (wsClient in wsClients) {
            remoteChatClient.disconnect()
            chat = chat.copy(config = directConfig, connectionStatus = "连接中", lastError = null)
            connectRemoteChat(directConfig, client = wsClient)
            try {
                waitForDirectRemoteChatReady()
                return null
            } catch (error: Throwable) {
                lastError = error
                remoteChatClient.disconnect()
            }
        }
        val failure = lastError ?: IllegalStateException("局域网连接失败。")
        chat = chat.copy(connectionStatus = "未连接", lastError = userMessage(failure, "局域网连接失败。"))
        return failure
    }

    private fun lanBoundClient(): OkHttpClient =
        LanNetworkSelector.wifiBoundClient(getApplication())
            ?: LanNetworkSelector.defaultLanClient()
}
