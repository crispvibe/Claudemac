package com.acode.android.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.net.URLEncoder
import java.util.concurrent.TimeUnit

class RemoteApiException(message: String) : Exception(message)

class RemoteApiClient(
    private val baseUrl: String = "https://acode.anna.vin",
    private val client: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .writeTimeout(30, TimeUnit.SECONDS)
        .build(),
) {
    private val jsonMediaType = "application/json; charset=utf-8".toMediaType()

    suspend fun requestRegisterCode(email: String): JSONObject = post(
        path = "remote/auth/register-code",
        body = JSONObject().put("email", email.trim().lowercase()),
    )

    suspend fun register(email: String, password: String, verificationCode: String): RemoteAuthSession =
        post(
            path = "remote/auth/register",
            body = JSONObject()
                .put("email", email.trim().lowercase())
                .put("password", password)
                .put("verificationCode", verificationCode.trim()),
        ).toAuthSession()

    suspend fun login(email: String, password: String): RemoteAuthSession =
        post(
            path = "remote/auth/login",
            body = JSONObject()
                .put("email", email.trim().lowercase())
                .put("password", password),
        ).toAuthSession()

    suspend fun refresh(refreshToken: String): RemoteAuthSession =
        post("remote/auth/refresh", JSONObject().put("refreshToken", refreshToken)).toAuthSession()

    suspend fun requestPasswordResetCode(email: String): JSONObject = post(
        path = "remote/auth/password-reset-code",
        body = JSONObject().put("email", email.trim().lowercase()),
    )

    suspend fun resetPassword(email: String, password: String, verificationCode: String) {
        post(
            path = "remote/auth/reset-password",
            body = JSONObject()
                .put("email", email.trim().lowercase())
                .put("password", password)
                .put("verificationCode", verificationCode.trim()),
        )
    }

    suspend fun legalDocument(type: String, platform: String = "android"): RemoteLegalDocument =
        get("remote/legal-documents?type=$type&platform=$platform").toLegalDocument()

    suspend fun checkAppUpdate(version: String, buildNumber: String): RemoteAppUpdateInfo {
        val encodedVersion = URLEncoder.encode(version, Charsets.UTF_8.name())
        val encodedBuild = URLEncoder.encode(buildNumber, Charsets.UTF_8.name())
        return get("remote/app-updates/check?platform=android&channel=stable&version=$encodedVersion&buildNumber=$encodedBuild").toAppUpdateInfo()
    }

    suspend fun consent(documentId: Int, deviceId: Int, accessToken: String) {
        post(
            path = "remote/legal-consents",
            body = JSONObject()
                .put("documentId", documentId)
                .put("platform", "android")
                .put("deviceId", deviceId),
            accessToken = accessToken,
        )
    }

    suspend fun registerDevice(identity: LocalDeviceIdentity, accessToken: String): RemoteDeviceInfo =
        post(
            path = "remote/devices/register",
            body = JSONObject()
                .put("deviceUid", identity.deviceUid)
                .put("deviceType", "android")
                .put("platform", "android")
                .put("deviceName", identity.deviceName)
                .put("devicePublicKey", identity.devicePublicKey)
                .put("appVersion", "1.0"),
            accessToken = accessToken,
        ).toDeviceInfo()

    suspend fun devices(accessToken: String): List<RemoteDeviceInfo> =
        getArray("remote/devices", accessToken).objects().map { it.toDeviceInfo() }

    suspend fun device(deviceId: Int, accessToken: String): RemoteDeviceInfo =
        get("remote/devices/$deviceId", accessToken).toDeviceInfo()

    suspend fun connect(deviceId: Int, identity: LocalDeviceIdentity, accessToken: String): RemoteConnectionAttempt {
        val fromDeviceId = identity.deviceId ?: throw RemoteApiException("本机设备尚未注册，请重新登录后再试。")
        return post(
            path = "remote/devices/$deviceId/connect",
            body = JSONObject()
                .put("fromDeviceId", fromDeviceId)
                .put("fromDeviceUid", identity.deviceUid)
                .put("fromDevicePublicKey", identity.devicePublicKey),
            accessToken = accessToken,
        ).toConnectionAttempt()
    }

    suspend fun resolveDeviceCode(deviceCode: String, identity: LocalDeviceIdentity, accessToken: String): RemoteDeviceResolveResponse {
        val fromDeviceId = identity.deviceId ?: throw RemoteApiException("本机设备尚未注册，请重新登录后再试。")
        return post(
            path = "remote/device-codes/resolve",
            body = JSONObject()
                .put("deviceCode", deviceCode.trim())
                .put("fromDeviceId", fromDeviceId)
                .put("fromDeviceUid", identity.deviceUid)
                .put("fromDevicePublicKey", identity.devicePublicKey),
            accessToken = accessToken,
        ).toDeviceResolveResponse()
    }

    suspend fun connection(connectionId: Int, accessToken: String): RemoteConnectionAttempt =
        get("remote/connections/$connectionId", accessToken).toConnectionAttempt()

    suspend fun iceServers(connectionId: Int, accessToken: String): RemoteIceConfiguration =
        get("remote/ice-config?connectionId=$connectionId", accessToken).toIceConfiguration()

    suspend fun reportConnectionMetrics(
        connectionId: Int,
        request: RemoteConnectionMetricsRequest,
        accessToken: String,
    ): RemoteConnectionAttempt =
        post(
            path = "remote/connections/$connectionId/metrics",
            body = JSONObject()
                .put("transport", request.transport)
                .apply {
                    request.firstPacketLatencyMs?.let { put("firstPacketLatencyMs", it) }
                    request.stage?.let { put("stage", it) }
                    request.path?.let { put("path", it) }
                },
            accessToken = accessToken,
        ).toConnectionAttempt()

    suspend fun changePassword(currentPassword: String, newPassword: String, accessToken: String) {
        post(
            path = "remote/auth/change-password",
            body = JSONObject()
                .put("currentPassword", currentPassword)
                .put("newPassword", newPassword),
            accessToken = accessToken,
        )
    }

    suspend fun deleteAccount(
        confirmAccount: String,
        confirmDestroy: String,
        confirmWaiveRights: String,
        reason: String,
        accessToken: String,
    ): JSONObject = post(
        path = "remote/account/deletion",
        body = JSONObject()
            .put("confirmAccount", confirmAccount)
            .put("confirmDestroy", confirmDestroy)
            .put("confirmWaiveRights", confirmWaiveRights)
            .put("reason", reason),
        accessToken = accessToken,
    )

    private suspend fun get(path: String, accessToken: String? = null): JSONObject = perform("GET", path, null, accessToken) as JSONObject

    private suspend fun getArray(path: String, accessToken: String? = null): JSONArray = perform("GET", path, null, accessToken) as JSONArray

    private suspend fun post(path: String, body: JSONObject, accessToken: String? = null): JSONObject =
        perform("POST", path, body, accessToken) as JSONObject

    private suspend fun perform(method: String, path: String, body: JSONObject?, accessToken: String?): Any = withContext(Dispatchers.IO) {
        val normalizedBase = baseUrl.trimEnd('/')
        val normalizedPath = path.trimStart('/')
        val builder = Request.Builder()
            .url("$normalizedBase/$normalizedPath")
            .header("Accept", "application/json")
        if (!accessToken.isNullOrBlank()) {
            builder.header("Authorization", "Bearer $accessToken")
        }
        if (method == "POST") {
            builder.post((body ?: JSONObject()).toString().toRequestBody(jsonMediaType))
        } else {
            builder.get()
        }
        client.newCall(builder.build()).execute().use { response ->
            val raw = response.body?.string().orEmpty()
            if (raw.isBlank()) {
                if (response.code == 401) throw RemoteApiException("未授权。")
                if (!response.isSuccessful) throw RemoteApiException("请求失败（HTTP ${response.code}）。")
                return@withContext successMessage()
            }
            val envelope = runCatching { JSONObject(raw) }.getOrElse { throw RemoteApiException("响应解析失败。") }
            val code = envelope.optInt("code", if (response.isSuccessful) 0 else response.code)
            val message = envelope.optString("msg", envelope.optString("message", ""))
            if (response.code == 401) throw RemoteApiException(message.ifBlank { "未授权。" })
            if (!response.isSuccessful) throw RemoteApiException(message.ifBlank { "请求失败（HTTP ${response.code}）。" })
            if (code != 0) throw RemoteApiException(message.ifBlank { "请求失败。" })
            if (!envelope.has("data") || envelope.isNull("data")) return@withContext successMessage(message)
            when (val data = envelope.get("data")) {
                is JSONObject -> data
                is JSONArray -> data
                else -> successMessage(message, data)
            }
        }
    }

    private fun successMessage(message: String = "", value: Any? = null): JSONObject =
        JSONObject()
            .put("success", true)
            .apply {
                if (message.isNotBlank()) {
                    put("message", message)
                    put("msg", message)
                }
                if (value != null) put("value", value)
            }
}
