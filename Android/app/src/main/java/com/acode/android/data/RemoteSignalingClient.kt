package com.acode.android.data

import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONObject
import java.net.URLEncoder
import java.util.concurrent.TimeUnit

class RemoteSignalingClient(
    private val baseUrl: String = "https://acode.anna.vin",
    private val client: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(0, TimeUnit.SECONDS)
        .pingInterval(20, TimeUnit.SECONDS)
        .build(),
) {
    var onPresenceUpdate: ((deviceId: Int, online: Boolean) -> Unit)? = null
    var onConnectDecision: ((RemoteConnectionAttempt) -> Unit)? = null
    var onRelay: ((connectionId: Int, payload: RemoteSignalingPayload) -> Unit)? = null
    var isConnected: Boolean = false
        private set

    private var webSocket: WebSocket? = null
    private var accessToken = ""
    private var deviceId: Int? = null
    private var shouldReconnect = false
    private var reconnectDelayMs = 1_000L
    private var connectionGeneration = 0

    fun start(accessToken: String, deviceId: Int) {
        stop()
        this.accessToken = accessToken
        this.deviceId = deviceId
        shouldReconnect = true
        reconnectDelayMs = 1_000L
        connect()
    }

    fun stop() {
        shouldReconnect = false
        isConnected = false
        connectionGeneration += 1
        webSocket?.close(1000, "client closing")
        webSocket = null
    }

    private fun connect() {
        val id = deviceId ?: return
        val generation = ++connectionGeneration
        val url = signalingUrl(accessToken)
        val request = Request.Builder().url(url).build()
        webSocket = client.newWebSocket(request, Listener(id, generation))
    }

    private fun scheduleReconnect(generation: Int) {
        if (!shouldReconnect) return
        if (generation != connectionGeneration) return
        isConnected = false
        val delay = reconnectDelayMs
        reconnectDelayMs = (reconnectDelayMs * 2).coerceAtMost(30_000L)
        Thread {
            Thread.sleep(delay)
            if (shouldReconnect && generation == connectionGeneration) connect()
        }.start()
    }

    private fun signalingUrl(token: String): String {
        val wsBase = if (baseUrl.startsWith("http://")) {
            baseUrl.replaceFirst("http://", "ws://")
        } else {
            baseUrl.replaceFirst("https://", "wss://")
        }.trimEnd('/')
        val encodedToken = URLEncoder.encode(token, "UTF-8")
        return "$wsBase/remote/signaling/ws?token=$encodedToken"
    }

    fun relay(connectionId: Int, toDeviceId: Int, payload: RemoteSignalingPayload): Boolean {
        if (!isConnected) return false
        val frame = JSONObject()
            .put("type", "relay")
            .put("connectionId", connectionId)
            .put("toDeviceId", toDeviceId)
            .put("payload", payload.toJson())
        return webSocket?.send(frame.toString()) ?: false
    }

    private inner class Listener(
        private val localDeviceId: Int,
        private val generation: Int,
    ) : WebSocketListener() {
        override fun onOpen(webSocket: WebSocket, response: Response) {
            if (generation != connectionGeneration) return
            webSocket.send(JSONObject().put("type", "hello").put("deviceId", localDeviceId).toString())
        }

        override fun onMessage(webSocket: WebSocket, text: String) {
            if (generation != connectionGeneration) return
            val event = runCatching { JSONObject(text) }.getOrNull() ?: return
            when (event.optString("type")) {
                "hello_ack" -> {
                    reconnectDelayMs = 1_000L
                    isConnected = true
                }
                "ping" -> webSocket.send(JSONObject().put("type", "pong").toString())
                "presence_update" -> {
                    val deviceId = event.intOrNull("deviceId") ?: return
                    onPresenceUpdate?.invoke(deviceId, event.optBoolean("online", false))
                }
                "connect_decision" -> {
                    event.optJSONObject("connection")?.let { onConnectDecision?.invoke(it.toConnectionAttempt()) }
                }
                "relay" -> {
                    val connectionId = event.intOrNull("connectionId", "connection_id") ?: return
                    val payload = event.optJSONObject("payload")?.toSignalingPayload() ?: return
                    onRelay?.invoke(connectionId, payload)
                }
            }
        }

        override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
            if (generation != connectionGeneration) return
            isConnected = false
            if (code == 1008 || code == 4001) {
                shouldReconnect = false
                return
            }
            scheduleReconnect(generation)
        }

        override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
            if (generation != connectionGeneration) return
            isConnected = false
            if (response?.code == 401 || response?.code == 403) {
                shouldReconnect = false
                return
            }
            scheduleReconnect(generation)
        }
    }
}
