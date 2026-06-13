package com.acode.android.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ChevronLeft
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material.icons.rounded.Computer
import androidx.compose.material.icons.rounded.ContentCopy
import androidx.compose.material.icons.rounded.ErrorOutline
import androidx.compose.material.icons.rounded.Numbers
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.acode.android.data.RemoteDeviceInfo
import com.acode.android.data.RemoteDeviceResolveResponse
import com.acode.android.ui.components.AcodeGlassCard
import com.acode.android.ui.components.AcodeIconButton
import com.acode.android.ui.components.BlackCapsuleButton
import com.acode.android.ui.components.SectionTitle
import com.acode.android.ui.components.SelectionPill
import com.acode.android.ui.components.WhiteGlassBackground
import com.acode.android.ui.theme.AcodeColor
import com.acode.android.ui.theme.AcodeRadius

private enum class DeviceConnectionMode {
    Devices,
    Code,
}

@Composable
fun DeviceListScreen(
    devices: List<RemoteDeviceInfo>,
    loading: Boolean,
    deviceCode: String,
    resolving: Boolean,
    connecting: Boolean,
    resolvedDevice: RemoteDeviceResolveResponse?,
    message: String?,
    connectedDeviceId: Int?,
    connectedTransport: String?,
    goBack: () -> Unit,
    refresh: () -> Unit,
    connect: (RemoteDeviceInfo) -> Unit,
    onCodeChange: (String) -> Unit,
    resolve: () -> Unit,
    connectResolved: () -> Unit,
) {
    var mode by remember { mutableStateOf(DeviceConnectionMode.Devices) }

    Box(Modifier.fillMaxSize()) {
        WhiteGlassBackground(Modifier.fillMaxSize())
        Column(
            Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .navigationBarsPadding()
                .imePadding()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 18.dp, vertical = 22.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            TopTitleBar(
                title = "远程设备",
                goBack = goBack,
                trailing = { LoggedInChip() },
            )
            DevicePageHeader(mode)
            SegmentedTabs(mode = mode, onModeChange = { mode = it })
            if (mode == DeviceConnectionMode.Devices) {
                DeviceSection(
                    devices = devices,
                    loading = loading,
                    message = message,
                    connectedDeviceId = connectedDeviceId,
                    connectedTransport = connectedTransport,
                    refresh = refresh,
                    connect = connect,
                )
                CodeEntryShortcut { mode = DeviceConnectionMode.Code }
            } else {
                DeviceCodeSection(
                    deviceCode = deviceCode,
                    resolving = resolving,
                    connecting = connecting,
                    resolvedDevice = resolvedDevice,
                    message = message,
                    onCodeChange = onCodeChange,
                    resolve = resolve,
                    connect = connectResolved,
                )
                ResolvedDeviceCard(resolvedDevice)
                BlackCapsuleButton(
                    text = if (connecting) "连接中..." else "连接这台电脑",
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(58.dp),
                    enabled = resolvedDevice != null && !connecting,
                    onClick = connectResolved,
                )
            }
        }
    }
}

@Composable
fun TopTitleBar(title: String, goBack: () -> Unit, trailing: (@Composable () -> Unit)? = null) {
    Box(
        Modifier
            .fillMaxWidth()
            .height(64.dp)
    ) {
        AcodeIconButton(
            imageVector = Icons.Rounded.ChevronLeft,
            contentDescription = "返回",
            modifier = Modifier.align(Alignment.CenterStart),
            onClick = goBack,
        )
        Text(
            title,
            color = AcodeColor.Ink,
            fontSize = 20.sp,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.align(Alignment.Center),
        )
        if (trailing != null) {
            Box(modifier = Modifier.align(Alignment.CenterEnd)) {
                trailing()
            }
        }
    }
}

@Composable
private fun DevicePageHeader(mode: DeviceConnectionMode) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            if (mode == DeviceConnectionMode.Devices) "选择电脑" else "输入设备码",
            color = AcodeColor.Ink,
            fontSize = 28.sp,
            fontWeight = FontWeight.Bold,
        )
        Text(
            if (mode == DeviceConnectionMode.Devices) {
                "连接已登录账号的远程设备，或输入设备码。"
            } else {
                "设备码在电脑端远程账号卡片中查看。"
            },
            color = AcodeColor.Muted,
            fontSize = 14.sp,
            lineHeight = 20.sp,
        )
    }
}

@Composable
private fun LoggedInChip() {
    AcodeGlassCard(corner = 20.dp, shadowAlpha = 0.02f) {
        Row(
            modifier = Modifier.padding(horizontal = 14.dp, vertical = 9.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                modifier = Modifier
                    .size(8.dp)
                    .clip(RoundedCornerShape(4.dp))
                    .background(AcodeColor.Green),
            )
            Text("已登录", color = AcodeColor.Muted, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
        }
    }
}

@Composable
private fun SegmentedTabs(mode: DeviceConnectionMode, onModeChange: (DeviceConnectionMode) -> Unit) {
    AcodeGlassCard(corner = AcodeRadius.Control, modifier = Modifier.fillMaxWidth(), shadowAlpha = 0.02f) {
        Row(Modifier.padding(5.dp)) {
            Box(
                modifier = Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(AcodeRadius.Control))
                    .clickable(onClick = { onModeChange(DeviceConnectionMode.Devices) }),
            ) {
                SelectionPill(
                    selected = mode == DeviceConnectionMode.Devices,
                    text = "我的设备",
                    modifier = Modifier.fillMaxWidth(),
                )
            }
            Box(
                modifier = Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(AcodeRadius.Control))
                    .clickable(onClick = { onModeChange(DeviceConnectionMode.Code) }),
            ) {
                SelectionPill(
                    selected = mode == DeviceConnectionMode.Code,
                    text = "设备码",
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }
    }
}

@Composable
private fun DeviceSection(
    devices: List<RemoteDeviceInfo>,
    loading: Boolean,
    message: String?,
    connectedDeviceId: Int?,
    connectedTransport: String?,
    refresh: () -> Unit,
    connect: (RemoteDeviceInfo) -> Unit,
) {
    AcodeGlassCard(corner = AcodeRadius.Control, modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                SectionTitle("我的设备", "来自当前账号的电脑", modifier = Modifier.weight(1f))
                RefreshChip(loading = loading, refresh = refresh)
            }
            when {
                loading && devices.isEmpty() -> LoadingState()
                devices.isEmpty() -> EmptyOrMessageState(message = message, refresh = refresh)
                else -> {
                    devices.forEach { device ->
                        DeviceRow(
                            device = device,
                            isConnected = device.id == connectedDeviceId,
                            connectedTransport = if (device.id == connectedDeviceId) connectedTransport else null,
                            connect = { connect(device) },
                        )
                    }
                    if (!message.isNullOrBlank()) {
                        Text(message, color = AcodeColor.Muted, fontSize = 12.sp, lineHeight = 17.sp)
                    }
                }
            }
        }
    }
}

@Composable
private fun DeviceRow(device: RemoteDeviceInfo, isConnected: Boolean, connectedTransport: String?, connect: () -> Unit) {
    val canConnect = device.canRequestConnection()
    val contentAlpha = if (canConnect || isConnected) 1f else 0.42f
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(22.dp))
            .background(Color.White.copy(alpha = if (isConnected) 0.72f else if (canConnect) 0.54f else 0.32f))
            .then(if (isConnected) Modifier.border(1.5.dp, AcodeColor.Ink.copy(alpha = 0.18f), RoundedCornerShape(22.dp)) else Modifier)
            .padding(horizontal = 14.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(
            modifier = Modifier
                .size(44.dp)
                .clip(RoundedCornerShape(14.dp))
                .background(Color.White.copy(alpha = if (canConnect || isConnected) 0.72f else 0.46f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                Icons.Rounded.Computer,
                contentDescription = null,
                tint = AcodeColor.Ink.copy(alpha = contentAlpha),
                modifier = Modifier.size(27.dp),
            )
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                device.deviceName,
                color = AcodeColor.Ink.copy(alpha = contentAlpha),
                fontSize = 16.sp,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                deviceSubtitle(device, isConnected, connectedTransport),
                color = AcodeColor.Muted.copy(alpha = if (canConnect || isConnected) 1f else 0.72f),
                fontSize = 13.sp,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
        }
        if (isConnected) {
            Text(
                connectedTransportLabel(connectedTransport),
                color = Color(0xFF2E7D32),
                fontSize = 13.sp,
                fontWeight = FontWeight.SemiBold,
            )
        } else if (canConnect) {
            BlackCapsuleButton(text = device.connectButtonText(), modifier = Modifier.height(44.dp), onClick = connect)
        }
    }
}

@Composable
private fun CodeEntryShortcut(openDeviceCode: () -> Unit) {
    AcodeGlassCard(corner = AcodeRadius.Control, modifier = Modifier.fillMaxWidth()) {
        Row(
            Modifier
                .clip(RoundedCornerShape(AcodeRadius.Control))
                .clickable(onClick = openDeviceCode)
                .padding(16.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                modifier = Modifier
                    .size(52.dp)
                    .clip(RoundedCornerShape(18.dp))
                    .background(Color.White.copy(alpha = 0.58f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Rounded.Numbers, contentDescription = null, tint = AcodeColor.Ink, modifier = Modifier.size(27.dp))
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text("输入设备码", color = AcodeColor.Ink, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
                Text("用电脑端显示的固定设备码连接", color = AcodeColor.Muted, fontSize = 13.sp)
            }
            Icon(Icons.Rounded.ChevronRight, contentDescription = null, tint = AcodeColor.Muted.copy(alpha = 0.55f), modifier = Modifier.size(24.dp))
        }
    }
}

@Composable
private fun DeviceCodeSection(
    deviceCode: String,
    resolving: Boolean,
    connecting: Boolean,
    resolvedDevice: RemoteDeviceResolveResponse?,
    message: String?,
    onCodeChange: (String) -> Unit,
    resolve: () -> Unit,
    connect: () -> Unit,
) {
    AcodeGlassCard(corner = AcodeRadius.Control, modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            SectionTitle("固定设备码", "支持 Mac / Windows / 其他桌面设备")
            TextField(
                value = deviceCode,
                onValueChange = onCodeChange,
                placeholder = { Text("ABCD-EFGH-12", color = AcodeColor.Muted.copy(alpha = 0.44f)) },
                trailingIcon = {
                    Icon(Icons.Rounded.ContentCopy, contentDescription = null, tint = AcodeColor.Muted, modifier = Modifier.size(28.dp))
                },
                colors = TextFieldDefaults.colors(
                    focusedContainerColor = Color.White.copy(alpha = 0.68f),
                    unfocusedContainerColor = Color.White.copy(alpha = 0.68f),
                    disabledContainerColor = Color.White.copy(alpha = 0.42f),
                    focusedIndicatorColor = Color.Transparent,
                    unfocusedIndicatorColor = Color.Transparent,
                    disabledIndicatorColor = Color.Transparent,
                ),
                shape = RoundedCornerShape(18.dp),
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                SecondaryActionButton(
                    text = if (resolving) "查找中..." else "查找设备",
                    loading = resolving,
                    enabled = !resolving,
                    onClick = resolve,
                    modifier = Modifier.weight(1f),
                )
                BlackCapsuleButton(
                    text = if (connecting) "连接中..." else "连接",
                    modifier = Modifier
                        .weight(1f)
                        .height(52.dp),
                    enabled = resolvedDevice != null && !connecting,
                    onClick = connect,
                )
            }
            Text("解析成功后显示设备名称和确认状态。", color = AcodeColor.Muted, fontSize = 12.sp, lineHeight = 17.sp)
            if (!message.isNullOrBlank()) {
                Text(message, color = AcodeColor.Muted, fontSize = 12.sp, lineHeight = 17.sp)
            }
        }
    }
}

@Composable
private fun ResolvedDeviceCard(resolvedDevice: RemoteDeviceResolveResponse?) {
    if (resolvedDevice == null) return
    AcodeGlassCard(corner = AcodeRadius.Control, modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(
                    modifier = Modifier
                        .size(52.dp)
                        .clip(RoundedCornerShape(17.dp))
                        .background(Color.White.copy(alpha = 0.64f)),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(Icons.Rounded.Computer, contentDescription = null, tint = AcodeColor.Ink, modifier = Modifier.size(30.dp))
                }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(
                        resolvedDevice.deviceName,
                        color = AcodeColor.Ink,
                        fontSize = 18.sp,
                        fontWeight = FontWeight.Bold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Text(
                        "${resolvedDevice.platform} · ${if (resolvedDevice.requiresConfirm) "需要电脑端确认" else "可直接连接"}",
                        color = AcodeColor.Muted,
                        fontSize = 13.sp,
                    )
                }
            }
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(1.dp)
                    .background(AcodeColor.Line),
            )
            Text("等待确认时保留在本页，不跳转、不遮挡主聊天页。", color = AcodeColor.Muted, fontSize = 12.sp, lineHeight = 17.sp)
        }
    }
}

@Composable
private fun RefreshChip(loading: Boolean, refresh: () -> Unit) {
    AcodeGlassCard(corner = 18.dp, shadowAlpha = 0.02f) {
        Row(
            modifier = Modifier
                .clip(RoundedCornerShape(18.dp))
                .clickable(enabled = !loading, onClick = refresh)
                .padding(horizontal = 14.dp, vertical = 9.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (loading) {
                CircularProgressIndicator(
                    modifier = Modifier.size(14.dp),
                    strokeWidth = 2.dp,
                    color = AcodeColor.Ink,
                    trackColor = AcodeColor.Line,
                )
            } else {
                Icon(Icons.Rounded.Refresh, contentDescription = null, tint = AcodeColor.Ink, modifier = Modifier.size(16.dp))
            }
            Text(
                if (loading) "刷新中" else "刷新",
                color = AcodeColor.Ink.copy(alpha = if (loading) 0.68f else 1f),
                fontSize = 14.sp,
                fontWeight = FontWeight.SemiBold,
            )
        }
    }
}

@Composable
private fun LoadingState() {
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(22.dp))
            .background(Color.White.copy(alpha = 0.54f))
            .padding(horizontal = 16.dp, vertical = 18.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        CircularProgressIndicator(
            modifier = Modifier.size(20.dp),
            strokeWidth = 2.5.dp,
            color = AcodeColor.Ink,
            trackColor = AcodeColor.Line,
        )
        Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text("正在刷新设备", color = AcodeColor.Ink, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
            Text("正在获取当前账号的桌面设备。", color = AcodeColor.Muted, fontSize = 12.sp)
        }
    }
}

@Composable
private fun EmptyOrMessageState(message: String?, refresh: () -> Unit) {
    val hasMessage = !message.isNullOrBlank()
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(22.dp))
            .background(Color.White.copy(alpha = 0.54f))
            .padding(horizontal = 16.dp, vertical = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier
                .size(44.dp)
                .clip(RoundedCornerShape(14.dp))
                .background(Color.White.copy(alpha = 0.72f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                if (hasMessage) Icons.Rounded.ErrorOutline else Icons.Rounded.Computer,
                contentDescription = null,
                tint = AcodeColor.Ink.copy(alpha = 0.72f),
                modifier = Modifier.size(25.dp),
            )
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(if (hasMessage) "暂时无法获取设备" else "还没有远程设备", color = AcodeColor.Ink, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
            Text(
                message?.takeIf { it.isNotBlank() } ?: "请先在电脑端登录同一账号并开启远程设备。",
                color = AcodeColor.Muted,
                fontSize = 12.sp,
                lineHeight = 17.sp,
            )
        }
        Text(
            "重试",
            modifier = Modifier
                .clip(RoundedCornerShape(18.dp))
                .clickable(onClick = refresh)
                .padding(horizontal = 12.dp, vertical = 9.dp),
            color = AcodeColor.Ink,
            fontSize = 13.sp,
            fontWeight = FontWeight.SemiBold,
        )
    }
}

@Composable
private fun SecondaryActionButton(
    text: String,
    loading: Boolean,
    enabled: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    AcodeGlassCard(corner = 18.dp, modifier = modifier.fillMaxWidth(), fill = Color.White.copy(alpha = 0.72f), shadowAlpha = 0.02f) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(52.dp)
                .clickable(enabled = enabled, onClick = onClick)
                .padding(horizontal = 16.dp),
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (loading) {
                CircularProgressIndicator(
                    modifier = Modifier.size(16.dp),
                    strokeWidth = 2.dp,
                    color = AcodeColor.Ink,
                    trackColor = AcodeColor.Line,
                )
                Spacer(Modifier.width(8.dp))
            }
            Text(
                text,
                color = AcodeColor.Ink.copy(alpha = if (enabled) 1f else 0.52f),
                fontSize = 14.sp,
                fontWeight = FontWeight.SemiBold,
            )
        }
    }
}

private fun deviceSubtitle(device: RemoteDeviceInfo, isConnected: Boolean = false, connectedTransport: String? = null): String {
    val platform = device.platform?.takeIf { it.isNotBlank() } ?: "macOS"
    if (isConnected) {
        return listOfNotNull(platform, connectedTransportLabel(connectedTransport)).joinToString(" · ")
    }
    val status = when {
        !device.remoteEnabled -> "远程关闭"
        !device.status.equals("active", ignoreCase = true) -> device.status.ifBlank { "不可连接" }
        !device.online -> "离线"
        else -> "在线"
    }
    val transport = when {
        device.hasDirectEndpoint() -> "局域网可连接"
        device.canRequestConnection() -> "信令可请求"
        !device.lastSeenAt.isNullOrBlank() -> "上次在线 ${device.lastSeenAt}"
        else -> null
    }
    return listOfNotNull(platform, status, transport).joinToString(" · ")
}

private fun connectedTransportLabel(transport: String?): String = when (transport) {
    "lan" -> "局域网入网"
    "public" -> "公网入网"
    "p2p" -> "跨网入网"
    "tunnel" -> "跨网入网"
    else -> "已连接"
}

private fun RemoteDeviceInfo.connectButtonText(): String =
    if (hasDirectEndpoint()) "连接" else "请求连接"
