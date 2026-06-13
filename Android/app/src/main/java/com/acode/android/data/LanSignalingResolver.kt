package com.acode.android.data

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONObject

/**
 * When the cloud lan-token API is unavailable, negotiate LAN endpoint + transient token
 * over the signaling tunnel immediately after connect is accepted.
 */
object LanSignalingResolver {
    suspend fun resolve(
        connectionId: Int,
        targetDeviceId: Int,
        signalingClient: RemoteSignalingClient,
        timeoutMs: Long = 15_000,
    ): RemoteChatConfig? = withContext(Dispatchers.IO) {
        if (!signalingClient.isConnected) return@withContext null

        val offer = CompletableDeferred<RemoteChatConfig?>()
        val previousTunnelHandler = signalingClient.onTunnelEvent

        signalingClient.onTunnelEvent = { type, eventConnectionId, frame, reason ->
            if (eventConnectionId == connectionId) {
                when (type) {
                    "tunnel_open_ack" -> {
                        signalingClient.sendTunnelFrame(
                            connectionId,
                            System.nanoTime(),
                            JSONObject().put("type", "lan_request").toString(),
                        )
                    }
                    "tunnel_frame" -> {
                        parseLanOffer(frame)?.let { config ->
                            if (!offer.isCompleted) offer.complete(config)
                        }
                    }
                }
            } else {
                previousTunnelHandler?.invoke(type, eventConnectionId, frame, reason)
            }
        }

        val opened = signalingClient.openTunnel(connectionId, targetDeviceId)
        if (!opened) {
            signalingClient.onTunnelEvent = previousTunnelHandler
            return@withContext null
        }
        signalingClient.sendTunnelFrame(
            connectionId,
            1,
            JSONObject().put("type", "lan_request").toString(),
        )

        try {
            withTimeoutOrNull(timeoutMs) { offer.await() }
        } finally {
            signalingClient.sendTunnelClose(connectionId, "lan_probe_done")
            signalingClient.onTunnelEvent = previousTunnelHandler
        }
    }

    private fun parseLanOffer(frame: String?): RemoteChatConfig? {
        val json = runCatching { JSONObject(frame.orEmpty()) }.getOrNull() ?: return null
        if (json.optString("type") != "lan_offer") return null
        val ip = json.optString("ip").trim()
        val port = json.optInt("port")
        val token = json.optString("token").trim()
        if (ip.isBlank() || port !in 1..65535 || token.isBlank()) return null
        return RemoteChatConfig(macHost = ip, port = port, token = token, transport = "lan")
    }
}
