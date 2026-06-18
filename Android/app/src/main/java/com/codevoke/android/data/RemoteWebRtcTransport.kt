package com.codevoke.android.data

import android.content.Context
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONObject
import org.webrtc.DataChannel
import org.webrtc.IceCandidate
import org.webrtc.MediaStream
import org.webrtc.PeerConnection
import org.webrtc.PeerConnectionFactory
import org.webrtc.RtpReceiver
import org.webrtc.SdpObserver
import org.webrtc.SessionDescription
import java.nio.ByteBuffer
import java.util.UUID

class RemoteWebRtcTransport(
    context: Context,
    private val connectionId: Int,
    private val targetDeviceId: Int,
    private val signalingClient: RemoteSignalingClient,
    iceServers: List<RemoteIceServer>,
) {
    var onStatus: ((String) -> Unit)? = null
    var onError: ((String?) -> Unit)? = null
    var onSnapshot: ((RemotePanelSnapshot) -> Unit)? = null
    var onPatch: ((RemotePanelPatch) -> Unit)? = null
    var onAck: ((commandId: String, status: String, message: String?, sessionId: String?) -> Unit)? = null

    @Volatile
    var isConnected: Boolean = false
        private set
    @Volatile
    var isTransportConnected: Boolean = false
        private set
    val isReady: Boolean get() = isConnected
    val canSendFrames: Boolean get() = dataChannel?.state() == DataChannel.State.OPEN

    private val factory = WebRtcFactoryProvider.factory(context.applicationContext)
    private val rtcIceServers = iceServers.flatMap { server ->
        server.urls.map { url ->
            PeerConnection.IceServer.builder(url)
                .setUsername(server.username.orEmpty())
                .setPassword(server.credential.orEmpty())
                .createIceServer()
        }
    }
    private var peerConnection: PeerConnection? = null
    private var dataChannel: DataChannel? = null
    private val pendingRemoteCandidates = mutableListOf<IceCandidate>()
    private var didSetRemoteDescription = false
    private var intentionallyClosed = false
    private var resumeSessionId: String? = null
    private var resumeLastRevision: Int? = null
    @Volatile
    private var readySignal: CompletableDeferred<Boolean> = CompletableDeferred()

    fun connect(focusedSessionId: String? = null, lastRevision: Int? = null) {
        disconnect()
        intentionallyClosed = false
        resumeSessionId = focusedSessionId
        resumeLastRevision = lastRevision
        onStatus?.invoke("连接中")
        resetReadySignal()
        isTransportConnected = false
        val configuration = PeerConnection.RTCConfiguration(rtcIceServers)
        configuration.sdpSemantics = PeerConnection.SdpSemantics.UNIFIED_PLAN
        peerConnection = factory.createPeerConnection(configuration, PeerObserver())
        val init = DataChannel.Init().apply { ordered = true }
        adoptDataChannel(peerConnection?.createDataChannel("chat", init))
        createOffer()
    }

    fun disconnect() {
        intentionallyClosed = true
        dataChannel?.close()
        peerConnection?.close()
        dataChannel = null
        peerConnection = null
        isTransportConnected = false
        completeReadySignal(false)
        pendingRemoteCandidates.clear()
        didSetRemoteDescription = false
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
        if (!sendText(frame.toString())) {
            onError?.invoke("远程通道暂不可用，正在等待连接恢复。")
        }
    }

    fun sendCommand(op: String, sessionId: String? = null, args: JSONObject = JSONObject(), commandId: String = UUID.randomUUID().toString()): String {
        val frame = JSONObject()
            .put("type", "command")
            .put("commandId", commandId)
            .put("op", op)
            .put("sessionId", sessionId)
            .put("args", args)
        if (!sendText(frame.toString())) {
            onError?.invoke("命令已排队，远程通道恢复后会重试。")
        }
        return commandId
    }

    fun receiveRelayPayload(payload: RemoteSignalingPayload) {
        when (payload.kind) {
            "offer" -> payload.sdp?.let {
                setRemoteDescription(SessionDescription(SessionDescription.Type.OFFER, it)) { createAnswer() }
            }
            "answer" -> payload.sdp?.let {
                setRemoteDescription(SessionDescription(SessionDescription.Type.ANSWER, it))
            }
            "candidate" -> {
                val candidate = payload.candidate ?: return
                addRemoteCandidate(IceCandidate(payload.sdpMid, payload.sdpMLineIndex ?: 0, candidate))
            }
            "failed" -> {
                isTransportConnected = false
                completeReadySignal(false)
                onStatus?.invoke("未连接")
                onError?.invoke(payload.message ?: "远程连接没有建立成功。")
            }
        }
    }

    private fun createOffer() {
        peerConnection?.createOffer(object : SimpleSdpObserver() {
            override fun onCreateSuccess(description: SessionDescription?) {
                val desc = description ?: return
                peerConnection?.setLocalDescription(object : SimpleSdpObserver() {
                    override fun onSetSuccess() {
                        relay(RemoteSignalingPayload(kind = "offer", sdp = desc.description))
                    }
                }, desc)
            }
        }, org.webrtc.MediaConstraints())
    }

    private fun createAnswer() {
        peerConnection?.createAnswer(object : SimpleSdpObserver() {
            override fun onCreateSuccess(description: SessionDescription?) {
                val desc = description ?: return
                peerConnection?.setLocalDescription(object : SimpleSdpObserver() {
                    override fun onSetSuccess() {
                        relay(RemoteSignalingPayload(kind = "answer", sdp = desc.description))
                    }
                }, desc)
            }
        }, org.webrtc.MediaConstraints())
    }

    private fun setRemoteDescription(description: SessionDescription, onSet: (() -> Unit)? = null) {
        peerConnection?.setRemoteDescription(object : SimpleSdpObserver() {
            override fun onSetSuccess() {
                didSetRemoteDescription = true
                val candidates = pendingRemoteCandidates.toList()
                pendingRemoteCandidates.clear()
                candidates.forEach { peerConnection?.addIceCandidate(it) }
                onSet?.invoke()
            }

            override fun onSetFailure(error: String?) {
                onError?.invoke(error ?: "WebRTC 远程描述设置失败。")
            }
        }, description)
    }

    private fun addRemoteCandidate(candidate: IceCandidate) {
        if (!didSetRemoteDescription) {
            pendingRemoteCandidates += candidate
            return
        }
        peerConnection?.addIceCandidate(candidate)
    }

    private fun adoptDataChannel(channel: DataChannel?) {
        val next = channel ?: return
        dataChannel = next
        next.registerObserver(ChannelObserver())
        if (next.state() == DataChannel.State.OPEN) handleChannelOpen()
    }

    private fun handleChannelOpen() {
        isTransportConnected = true
        onStatus?.invoke("连接中")
        sendResume(resumeSessionId, resumeLastRevision)
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
        if (!isConnected) onStatus?.invoke("已连接")
        completeReadySignal(true)
    }

    private fun sendText(text: String): Boolean {
        val channel = dataChannel ?: return false
        if (channel.state() != DataChannel.State.OPEN) return false
        val buffer = DataChannel.Buffer(ByteBuffer.wrap(text.toByteArray(Charsets.UTF_8)), false)
        return channel.send(buffer)
    }

    private fun relay(payload: RemoteSignalingPayload) {
        if (!signalingClient.relay(connectionId, targetDeviceId, payload)) {
            onError?.invoke("信令通道暂不可用，无法转发远程连接握手。")
        }
    }

    private inner class PeerObserver : PeerConnection.Observer {
        override fun onSignalingChange(state: PeerConnection.SignalingState?) = Unit
        override fun onIceConnectionReceivingChange(receiving: Boolean) = Unit
        override fun onIceGatheringChange(state: PeerConnection.IceGatheringState?) = Unit
        override fun onIceCandidatesRemoved(candidates: Array<out IceCandidate>?) = Unit
        override fun onAddStream(stream: MediaStream?) = Unit
        override fun onRemoveStream(stream: MediaStream?) = Unit
        override fun onRenegotiationNeeded() = Unit
        override fun onAddTrack(receiver: RtpReceiver?, mediaStreams: Array<out MediaStream>?) = Unit

        override fun onIceConnectionChange(state: PeerConnection.IceConnectionState?) {
            when (state) {
                PeerConnection.IceConnectionState.CONNECTED,
                PeerConnection.IceConnectionState.COMPLETED -> if (canSendFrames && !isReady) onStatus?.invoke("连接中")
                PeerConnection.IceConnectionState.FAILED,
                PeerConnection.IceConnectionState.DISCONNECTED -> {
                    isTransportConnected = false
                    completeReadySignal(false)
                    onStatus?.invoke("未连接")
                    if (!intentionallyClosed) onError?.invoke("远程连接没有建立成功，请确认设备在线后重试。")
                }
                else -> Unit
            }
        }

        override fun onIceCandidate(candidate: IceCandidate?) {
            val next = candidate ?: return
            relay(
                RemoteSignalingPayload(
                    kind = "candidate",
                    sdpMid = next.sdpMid,
                    sdpMLineIndex = next.sdpMLineIndex,
                    candidate = next.sdp,
                ),
            )
        }

        override fun onDataChannel(channel: DataChannel?) {
            adoptDataChannel(channel)
        }
    }

    private inner class ChannelObserver : DataChannel.Observer {
        override fun onBufferedAmountChange(previousAmount: Long) = Unit

        override fun onStateChange() {
            when (dataChannel?.state()) {
                DataChannel.State.OPEN -> handleChannelOpen()
                DataChannel.State.CLOSED -> {
                    isTransportConnected = false
                    completeReadySignal(false)
                    onStatus?.invoke("未连接")
                    if (!intentionallyClosed) onError?.invoke("远程通道已断开。")
                }
                else -> Unit
            }
        }

        override fun onMessage(buffer: DataChannel.Buffer?) {
            val data = buffer?.data ?: return
            val bytes = ByteArray(data.remaining())
            data.get(bytes)
            handleTextFrame(String(bytes, Charsets.UTF_8))
        }
    }

    private open class SimpleSdpObserver : SdpObserver {
        override fun onCreateSuccess(description: SessionDescription?) = Unit
        override fun onSetSuccess() = Unit
        override fun onCreateFailure(error: String?) = Unit
        override fun onSetFailure(error: String?) = Unit
    }
}

private object WebRtcFactoryProvider {
    @Volatile
    private var initialized = false

    @Synchronized
    fun factory(context: Context): PeerConnectionFactory {
        if (!initialized) {
            PeerConnectionFactory.initialize(
                PeerConnectionFactory.InitializationOptions
                    .builder(context)
                    .createInitializationOptions(),
            )
            initialized = true
        }
        return PeerConnectionFactory.builder().createPeerConnectionFactory()
    }
}
