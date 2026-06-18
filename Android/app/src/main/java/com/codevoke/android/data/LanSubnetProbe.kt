package com.codevoke.android.data

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.concurrent.TimeUnit

object LanSubnetProbe {
    suspend fun discoverHealthHost(
        context: Context,
        port: Int,
        preferredHost: String? = null,
    ): String? = withContext(Dispatchers.IO) {
        val client = LanNetworkSelector.wifiBoundClient(context, connectTimeoutSeconds = 1)
            ?: OkHttpClient.Builder()
                .connectTimeout(1, TimeUnit.SECONDS)
                .readTimeout(1, TimeUnit.SECONDS)
                .build()
        preferredHost?.takeIf { it.isNotBlank() }?.let { host ->
            if (healthOk(client, host, port)) return@withContext host
        }
        val prefix = LanNetworkSelector.wifiSubnetPrefix(context) ?: return@withContext null
        coroutineScope {
            (1..254).chunked(40).forEach { chunk ->
                val found = chunk.map { host ->
                    async {
                        val ip = "$prefix.$host"
                        if (ip == preferredHost) null else if (healthOk(client, ip, port)) ip else null
                    }
                }.awaitAll().firstOrNull { !it.isNullOrBlank() }
                if (found != null) return@coroutineScope found
            }
            null
        }
    }

    private fun healthOk(client: OkHttpClient, host: String, port: Int): Boolean =
        runCatching {
            val request = Request.Builder().url("http://$host:$port/health").build()
            client.newCall(request).execute().use { it.isSuccessful }
        }.getOrDefault(false)
}
