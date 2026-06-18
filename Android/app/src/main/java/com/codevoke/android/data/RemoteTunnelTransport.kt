package com.codevoke.android.data

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONObject
import java.util.UUID
import java.util.concurrent.atomic.AtomicLong

class RemoteTunnelTransport(
    private val connectionId: Int,
    private val targetDeviceId: Int,
    private val signalingClient: RemoteSignalingClient,
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.IO),
) {
    var onStatus: ((String) -> Unit)? = null
    var onError: ((String?) -> Unit)? = null
    var onSnapshot: ((RemotePanelSnapshot) -> Unit)? = null
    var onPatch: ((RemotePanelPatch) -> Unit)? = null
    var onAck: ((commandId: String, status: String, message: String?, sessionId: String?) -> Unit)? = null

    @Volatile
    var isConnected: Boolean = false
        private set
    val isReady: Boolean get() = isConnected

    private val nextSeq = AtomicLong(1)
    private var intentionallyClosed = false
    private var reconnectAttempt = 0
    private var reconnectJob: Job? = null
    private var lastSessionId: String? = null
    private var lastRevision: Int? = null
    @Volatile
    private var readySignal: CompletableDeferred<Boolean> = CompletableDeferred()

    fun connect(focusedSessionId: String? = null, lastRevision: Int? = null) {
        reconnectJob?.cancel()
        reconnectJob = null
        intentionallyClosed = false
        resetReadySignal()
        lastSessionId = focusedSessionId
        this.lastRevision = lastRevision
        onStatus?.invoke("连接中")

        signalingClient.onTunnelEvent = { type, eventConnectionId, frame, reason ->
            if (eventConnectionId == connectionId) {
                handleTunnelEvent(type, frame, reason)
            }
        }

        if (!signalingClient.openTunnel(connectionId, targetDeviceId)) {
            onStatus?.invoke("未连接")
            onError?.invoke("信令通道暂不可用，无法建立远程通道。")
            completeReadySignal(false)
            return
        }

        sendResume(focusedSessionId, lastRevision)
    }

    fun disconnect() {
        intentionallyClosed = true
        reconnectJob?.cancel()
        reconnectJob = null
        if (isConnected) {
            signalingClient.sendTunnelClose(connectionId, "client_disconnect")
        }
        signalingClient.onTunnelEvent = null
        isConnected = false
        completeReadySignal(false)
    }

    suspend fun awaitReady(timeoutMillis: Long? = null): Boolean {
        if (isReady) return true
        val signal = readySignal
        return if (timeoutMillis == null) {
            signal.await()
        } else {
            withTimeoutOrNull(timeoutMillis) { signal.await() } ?: false
        }
    }

    fun sendResume(sessionId: String?, lastRevision: Int?) {
        val frame = JSONObject()
            .put("type", "resume")
            .put("sessionId", sessionId)
            .put("lastRevision", lastRevision)
        sendFrame(frame.toString())
    }

    fun sendCommand(op: String, sessionId: String? = null, args: JSONObject = JSONObject(), commandId: String = UUID.randomUUID().toString()): String {
        val frame = JSONObject()
            .put("type", "command")
            .put("commandId", commandId)
            .put("op", op)
            .put("sessionId", sessionId)
            .put("args", args)
        if (!sendFrame(frame.toString())) {
            onError?.invoke("命令已排队，远程通道恢复后会重试。")
        }
        return commandId
    }

    private fun handleTunnelEvent(type: String, frame: String?, reason: String?) {
        if (intentionallyClosed) return
        when (type) {
            "tunnel_open_ack" -> {
                if (!isConnected) {
                    markReady()
                }
            }
            "tunnel_frame" -> {
                frame?.let { handleTextFrame(it) }
            }
            "tunnel_close" -> {
                isConnected = false
                completeReadySignal(false)
                if (!intentionallyClosed) {
                    onStatus?.invoke("重连中")
                    scheduleReconnect()
                }
            }
            "tunnel_error" -> {
                isConnected = false
                completeReadySignal(false)
                if (!intentionallyClosed) {
                    onStatus?.invoke("重连中")
                    scheduleReconnect()
                }
            }
        }
    }

    private fun handleTextFrame(text: String) {
        val json = runCatching { JSONObject(text) }.getOrNull() ?: return
        when (json.optString("type")) {
            "panel_state" -> {
                markReady()
                when (json.optString("kind")) {
                    "snapshot" -> json.optJSONObject("snapshot")?.let { onSnapshot?.invoke(it.toPanelSnapshot()) }
                    "patch" -> json.optJSONObject("patch")?.let { onPatch?.invoke(it.toPanelPatch()) }
                }
            }
            "command_ack" -> {
                markReady()
                onAck?.invoke(
                    json.optString("commandId"),
                    json.optString("status"),
                    json.stringOrNull("message"),
                    json.stringOrNull("sessionId"),
                )
            }
            "hello" -> markReady()
        }
    }

    private fun sendFrame(text: String): Boolean {
        if (!signalingClient.isConnected) return false
        val seq = nextSeq.getAndIncrement()
        return signalingClient.sendTunnelFrame(connectionId, seq, text)
    }

    private fun resetReadySignal() {
        isConnected = false
        completeReadySignal(false)
        readySignal = CompletableDeferred()
    }

    private fun completeReadySignal(ready: Boolean) {
        isConnected = ready
        if (readySignal.isCompleted) readySignal = CompletableDeferred()
        if (!readySignal.isCompleted) readySignal.complete(ready)
    }

    private fun markReady() {
        reconnectAttempt = 0
        if (!isConnected) onStatus?.invoke("已连接")
        completeReadySignal(true)
    }

    private fun scheduleReconnect() {
        if (intentionallyClosed) return
        val delaySeconds = when (reconnectAttempt.coerceAtMost(5)) {
            0 -> 1L; 1 -> 2L; 2 -> 4L; 3 -> 8L; 4 -> 16L; else -> 30L
        }
        reconnectAttempt++
        reconnectJob?.cancel()
        reconnectJob = scope.launch {
            delay(delaySeconds * 1000)
            if (intentionallyClosed) return@launch
            if (!signalingClient.isConnected) {
                onStatus?.invoke("未连接")
                onError?.invoke("信令通道已断开，等待恢复。")
                return@launch
            }
            onStatus?.invoke("连接中")
            resetReadySignal()
            if (!signalingClient.openTunnel(connectionId, targetDeviceId)) {
                onStatus?.invoke("重连中")
                scheduleReconnect()
                return@launch
            }
            sendResume(lastSessionId, lastRevision)
        }
    }
}
