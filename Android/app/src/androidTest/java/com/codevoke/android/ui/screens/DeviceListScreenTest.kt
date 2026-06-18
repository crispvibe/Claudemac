package com.codevoke.android.ui.screens

import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import com.codevoke.android.data.RemoteDeviceInfo
import com.codevoke.android.ui.theme.CodevokeTheme
import org.junit.Rule
import org.junit.Test

class DeviceListScreenTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun offlineDeviceShowsNoConnectAction() {
        composeRule.setContent {
            CodevokeTheme {
                DeviceListScreen(
                    devices = listOf(remoteDevice(online = false, lastSeenAt = "2026-05-28T00:00:00Z")),
                    loading = false,
                    deviceCode = "",
                    resolving = false,
                    connecting = false,
                    resolvedDevice = null,
                    message = null,
                    connectedDeviceId = null,
                    connectedTransport = null,
                    goBack = {},
                    refresh = {},
                    connect = {},
                    onCodeChange = {},
                    resolve = {},
                    connectResolved = {},
                )
            }
        }

        composeRule.onNodeWithText("离线", substring = true).assertExists()
        composeRule.onAllNodesWithText("请求连接").assertCountEquals(0)
        composeRule.onAllNodesWithText("连接").assertCountEquals(0)
    }

    @Test
    fun onlineDeviceWithoutDirectEndpointShowsRequestConnection() {
        composeRule.setContent {
            CodevokeTheme {
                DeviceListScreen(
                    devices = listOf(remoteDevice(online = true)),
                    loading = false,
                    deviceCode = "",
                    resolving = false,
                    connecting = false,
                    resolvedDevice = null,
                    message = null,
                    connectedDeviceId = null,
                    connectedTransport = null,
                    goBack = {},
                    refresh = {},
                    connect = {},
                    onCodeChange = {},
                    resolve = {},
                    connectResolved = {},
                )
            }
        }

        composeRule.onNodeWithText("信令可请求", substring = true).assertExists()
        composeRule.onNodeWithText("请求连接").assertExists()
    }

    private fun remoteDevice(
        online: Boolean,
        lastSeenAt: String? = null,
    ) = RemoteDeviceInfo(
        id = 42,
        userId = 1,
        deviceUid = "device-42",
        deviceName = "Office Mac",
        deviceType = "desktop",
        platform = "macOS",
        approvalPolicy = "always_ask",
        remoteEnabled = true,
        status = "active",
        online = online,
        lastSeenAt = lastSeenAt,
        lanEndpoint = null,
        transientToken = null,
    )
}
