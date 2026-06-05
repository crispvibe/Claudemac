package com.acode.android.data

import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import android.provider.Settings
import android.util.Log
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import org.json.JSONObject
import java.security.MessageDigest
import java.util.Locale
import java.util.UUID

class RemoteSessionStore(context: Context) {
    private val appContext = context.applicationContext
    private val prefs = SecurePrefs.open(appContext, PREFS_NAME)

    fun load(): RemoteAuthSession? {
        val raw = prefs.getString("session", null) ?: return null
        return runCatching { JSONObject(raw).toAuthSession() }.getOrNull()
    }

    fun save(session: RemoteAuthSession) {
        val user = JSONObject()
            .put("id", session.user.id)
            .put("email", session.user.email)
            .put("phone", session.user.phone)
            .put("status", session.user.status)
        val json = JSONObject()
            .put("accessToken", session.accessToken)
            .put("refreshToken", session.refreshToken)
            .put("expiresAt", session.expiresAt)
            .put("user", user)
        prefs.edit().putString("session", json.toString()).apply()
    }

    fun clear() {
        SecurePrefs.clearAll(appContext, PREFS_NAME, prefs)
    }

    private companion object {
        const val PREFS_NAME = "acode.remote.session"
    }
}

class LocalDeviceIdentityStore(context: Context) {
    private val appContext = context.applicationContext
    private val prefs = SecurePrefs.open(appContext, "acode.remote.identity")

    @Synchronized
    fun identity(): LocalDeviceIdentity {
        val editor = prefs.edit()
        var changed = false
        val uid = prefs.getString(KEY_DEVICE_UID, null)?.takeIf { it.isNotBlank() } ?: stableDeviceUid().also {
            editor.putString(KEY_DEVICE_UID, it)
            changed = true
        }
        val publicKey = prefs.getString(KEY_DEVICE_PUBLIC_KEY, null)?.takeIf { it.isNotBlank() } ?: UUID.randomUUID().toString().also {
            editor.putString(KEY_DEVICE_PUBLIC_KEY, it)
            changed = true
        }
        val deviceName = prefs.getString(KEY_DEVICE_NAME, null)?.takeIf { it.isNotBlank() } ?: defaultDeviceName().also {
            editor.putString(KEY_DEVICE_NAME, it)
            changed = true
        }
        if (changed && !editor.commit()) {
            error("本机设备身份保存失败，请检查应用存储权限。")
        }
        return LocalDeviceIdentity(
            deviceUid = uid,
            devicePublicKey = publicKey,
            deviceName = deviceName,
            deviceId = if (prefs.contains("deviceId")) prefs.getInt("deviceId", 0) else null,
        )
    }

    @Synchronized
    fun updateDeviceId(deviceId: Int) {
        if (!prefs.edit().putInt(KEY_DEVICE_ID, deviceId).commit()) {
            error("本机设备编号保存失败，请稍后重试。")
        }
    }

    @Synchronized
    fun clearDeviceId() {
        if (!prefs.edit().remove(KEY_DEVICE_ID).commit()) {
            error("本机设备编号清理失败，请稍后重试。")
        }
    }

    private fun stableDeviceUid(): String {
        val androidId = Settings.Secure.getString(appContext.contentResolver, Settings.Secure.ANDROID_ID)
            ?.takeIf { it.isNotBlank() && it != BROKEN_ANDROID_ID }
        if (androidId != null) {
            return "android-${sha256("${appContext.packageName}:$androidId").take(32)}"
        }
        return "android-${UUID.randomUUID()}"
    }

    private fun defaultDeviceName(): String {
        val manufacturer = Build.MANUFACTURER.orEmpty().trim()
        val model = Build.MODEL.orEmpty().trim()
        val raw = listOf(manufacturer, model)
            .filter { it.isNotBlank() }
            .joinToString(" ")
            .replace(Regex("\\s+"), " ")
            .trim()
        return raw.ifBlank { "Android" }.replaceFirstChar {
            if (it.isLowerCase()) it.titlecase(Locale.getDefault()) else it.toString()
        }
    }

    private fun sha256(value: String): String {
        val bytes = MessageDigest.getInstance("SHA-256").digest(value.toByteArray())
        return bytes.joinToString("") { "%02x".format(it) }
    }

    private companion object {
        const val KEY_DEVICE_UID = "deviceUid"
        const val KEY_DEVICE_PUBLIC_KEY = "devicePublicKey"
        const val KEY_DEVICE_NAME = "deviceName"
        const val KEY_DEVICE_ID = "deviceId"
        const val BROKEN_ANDROID_ID = "9774d56d682e549c"
    }
}

data class LocalDeviceIdentity(
    val deviceUid: String,
    val devicePublicKey: String,
    val deviceName: String,
    val deviceId: Int?,
)

private object SecurePrefs {
    private const val TAG = "AcodeStores"
    private const val SECURE_SUFFIX = ".secure"
    private const val KEY_CLEAR_MARKER = "__secure_prefs_clear_marker"

    fun open(context: Context, name: String): SharedPreferences {
        val legacy = context.getSharedPreferences(name, Context.MODE_PRIVATE)
        return runCatching {
            openEncrypted(context, name).also { encrypted ->
                if (legacy.hasOnlyClearMarker()) {
                    encrypted.edit().clear().apply()
                    legacy.edit().clear().apply()
                } else {
                    migrateLegacy(name, legacy, encrypted)
                }
            }
        }.getOrElse { error ->
            Log.w(TAG, "Encrypted preferences unavailable for $name; using private app storage fallback.", error)
            legacy
        }
    }

    fun clearAll(context: Context, name: String, active: SharedPreferences) {
        active.edit().clear().apply()
        val legacy = context.getSharedPreferences(name, Context.MODE_PRIVATE)
        legacy.edit().clear().putLong(KEY_CLEAR_MARKER, System.currentTimeMillis()).apply()
        runCatching {
            openEncrypted(context, name).edit().clear().apply()
            legacy.edit().clear().apply()
        }.onFailure { error ->
            Log.w(TAG, "Encrypted preferences clear deferred for $name; fallback marker kept.", error)
        }
    }

    private fun openEncrypted(context: Context, name: String): SharedPreferences {
        val masterKey = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        return EncryptedSharedPreferences.create(
            context,
            "$name$SECURE_SUFFIX",
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    }

    private fun migrateLegacy(name: String, legacy: SharedPreferences, encrypted: SharedPreferences) {
        val entries = legacy.all.filterKeys { it != KEY_CLEAR_MARKER }
        if (entries.isEmpty()) return

        val editor = encrypted.edit()
        var copiedAll = true
        var changed = false
        for ((key, value) in entries) {
            if (encrypted.contains(key)) continue
            changed = true
            copiedAll = editor.putValue(key, value) && copiedAll
        }
        if ((!changed || editor.commit()) && copiedAll) {
            legacy.edit().clear().apply()
        } else {
            Log.w(TAG, "Legacy preferences migration was incomplete for $name; keeping fallback copy.")
        }
    }

    private fun SharedPreferences.Editor.putValue(key: String, value: Any?): Boolean {
        when (value) {
            is String -> putString(key, value)
            is Int -> putInt(key, value)
            is Long -> putLong(key, value)
            is Float -> putFloat(key, value)
            is Boolean -> putBoolean(key, value)
            is Set<*> -> {
                val strings = value.mapNotNull { it as? String }.toSet()
                if (strings.size != value.size) return false
                putStringSet(key, strings)
            }
            null -> remove(key)
            else -> return false
        }
        return true
    }

    private fun SharedPreferences.hasOnlyClearMarker(): Boolean {
        val keys = all.keys
        return keys.isNotEmpty() && keys.all { it == KEY_CLEAR_MARKER }
    }
}
