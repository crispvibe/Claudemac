package com.acode.android.ui.screens

import android.os.Build
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.Logout
import androidx.compose.material.icons.rounded.AccountCircle
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material.icons.rounded.Code
import androidx.compose.material.icons.rounded.Computer
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.Description
import androidx.compose.material.icons.rounded.Download
import androidx.compose.material.icons.rounded.Info
import androidx.compose.material.icons.rounded.Lock
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.LocalContext
import com.acode.android.data.RemoteApiClient
import com.acode.android.data.RemoteLegalDocument
import com.acode.android.ui.components.BlackCapsuleButton
import com.acode.android.ui.components.WhiteGlassBackground
import com.acode.android.ui.theme.AcodeColor
import kotlinx.coroutines.launch

@Composable
fun SettingsScreen(
    account: String,
    connectionStatus: String,
    selectedCLI: String,
    goBack: () -> Unit,
    openAccount: () -> Unit,
    openDevices: () -> Unit,
    openLegal: () -> Unit,
) {
    val uriHandler = LocalUriHandler.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val updateClient = remember { RemoteApiClient() }
    val packageInfo = remember {
        runCatching { context.packageManager.getPackageInfo(context.packageName, 0) }.getOrNull()
    }
    val versionName = packageInfo?.versionName.orEmpty().ifBlank { "1.0" }
    val versionCode = remember(packageInfo) {
        packageInfo?.let {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                it.longVersionCode.toString()
            } else {
                @Suppress("DEPRECATION")
                val legacyVersionCode = it.versionCode
                legacyVersionCode.toString()
            }
        }.orEmpty().ifBlank { "1" }
    }
    val versionText = "版本 $versionName ($versionCode)"
    var updateMessage by remember { mutableStateOf<String?>(null) }
    var updateUrl by remember { mutableStateOf<String?>(null) }
    var checkingUpdate by remember { mutableStateOf(false) }

    Box(Modifier.fillMaxSize()) {
        WhiteGlassBackground(Modifier.fillMaxSize())
        Column(
            Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp, vertical = 22.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            TopTitleBar(title = "设置", goBack = goBack)
            SettingsSectionCard {
                Column {
                    SettingsMenuRow("账号与安全", account.ifBlank { "已登录" }, Icons.Rounded.AccountCircle, onClick = openAccount)
                    SettingsDivider()
                    SettingsMenuRow("协议与隐私", "用户协议、隐私政策", Icons.Rounded.Description, onClick = openLegal)
                }
            }
            SettingsSectionCard {
                Column {
                    SettingsMenuRow("远程设备", connectionStatus, Icons.Rounded.Computer, onClick = openDevices)
                    SettingsDivider()
                    SettingsMenuRow("CLI", if (selectedCLI == "codex") "Codex" else "Claude Code", Icons.Rounded.Code)
                }
            }
            SettingsSectionCard {
                Column {
                    SettingsMenuRow(
                        "在线更新",
                        updateMessage ?: versionText,
                        Icons.Rounded.Download,
                        onClick = {
                            scope.launch {
                                checkingUpdate = true
                                updateMessage = "正在检查更新..."
                                updateUrl = null
                                runCatching {
                                    updateClient.checkAppUpdate(versionName, versionCode)
                                }.onSuccess { info ->
                                    if (info.updateAvailable) {
                                        updateUrl = info.downloadUrl.ifBlank { info.appStoreUrl }
                                        val build = info.latestBuildNumber.ifBlank { "" }.let { if (it.isBlank()) "" else " ($it)" }
                                        val force = if (info.forceUpdate) "，这是强制更新" else ""
                                        updateMessage = "发现新版 ${info.latestVersion}$build$force"
                                    } else {
                                        updateMessage = "当前已是最新版本"
                                    }
                                }.onFailure { error ->
                                    updateMessage = error.message ?: "检查失败"
                                }
                                checkingUpdate = false
                            }
                        },
                    )
                    if (!updateUrl.isNullOrBlank()) {
                        SettingsDivider()
                        SettingsMenuRow("下载新版", "打开下载链接", Icons.Rounded.Download, onClick = { uriHandler.openUri(updateUrl.orEmpty()) })
                    }
                    SettingsDivider()
                    SettingsMenuRow("关于 AnnaCode", if (checkingUpdate) "检查中..." else versionText, Icons.Rounded.Info, showChevron = false)
                }
            }
        }
    }
}

@Composable
fun LegalScreen(documents: Map<String, RemoteLegalDocument>, goBack: () -> Unit) {
    val userAgreement = documents["user_agreement"]
    val privacyPolicy = documents["privacy_policy"]
    Box(Modifier.fillMaxSize()) {
        WhiteGlassBackground(Modifier.fillMaxSize())
        Column(
            Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp, vertical = 22.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            TopTitleBar(title = "协议与隐私", goBack = goBack)
            SettingsSectionCard {
                Column(
                    modifier = Modifier.padding(horizontal = 18.dp, vertical = 18.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Text(userAgreement?.title ?: "用户协议", color = AcodeColor.Ink, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
                    Text(userAgreement?.content ?: "协议内容暂时无法加载。", color = AcodeColor.Muted, fontSize = 14.sp, lineHeight = 22.sp)
                    SettingsDivider(modifier = Modifier.padding(start = 0.dp))
                    Text(privacyPolicy?.title ?: "隐私政策", color = AcodeColor.Ink, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
                    Text(privacyPolicy?.content ?: "隐私政策内容暂时无法加载。", color = AcodeColor.Muted, fontSize = 14.sp, lineHeight = 22.sp)
                }
            }
        }
    }
}

@Composable
fun AccountSecurityScreen(
    account: String,
    message: String?,
    goBack: () -> Unit,
    openChangePassword: () -> Unit,
    openDeleteAccount: () -> Unit,
    logout: () -> Unit,
) {
    Box(Modifier.fillMaxSize()) {
        WhiteGlassBackground(Modifier.fillMaxSize())
        Column(
            Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp, vertical = 22.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            TopTitleBar(title = "账号与安全", goBack = goBack)
            SettingsSectionCard {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    SettingsCardTitle("当前账号", "AnnaCode 远程账号")
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        SettingsPlainIcon(
                            icon = Icons.Rounded.AccountCircle,
                            tint = AcodeColor.Ink,
                            size = 28.dp,
                            frame = 31.dp,
                        )
                        Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                            Text(account.ifBlank { "已登录" }, color = AcodeColor.Ink, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
                            Text("状态正常", color = AcodeColor.Muted, fontSize = 12.sp)
                        }
                        Spacer(Modifier.weight(1f))
                    }
                }
            }
            SettingsSectionCard {
                Column {
                    SettingsMenuRow("修改密码", "使用当前密码验证", Icons.Rounded.Lock, onClick = openChangePassword)
                    SettingsDivider()
                    SettingsActionRow("退出登录", "清除本机登录状态", Icons.AutoMirrored.Rounded.Logout, tint = Color.Red.copy(alpha = 0.85f), onClick = logout)
                    SettingsDivider()
                    SettingsActionRow("注销账号", "删除账号与远程服务数据", Icons.Rounded.Delete, tint = Color.Red, onClick = openDeleteAccount)
                }
            }
            SettingsMessage(message)
        }
    }
}

@Composable
fun ChangePasswordScreen(
    currentPassword: String,
    newPassword: String,
    confirmPassword: String,
    submitting: Boolean,
    message: String?,
    onCurrentChange: (String) -> Unit,
    onNewChange: (String) -> Unit,
    onConfirmChange: (String) -> Unit,
    submit: () -> Unit,
    goBack: () -> Unit,
) {
    val canSubmit = currentPassword.isNotBlank() &&
        newPassword.length >= 6 &&
        newPassword == confirmPassword &&
        !submitting
    SettingsFormScreen(title = "修改密码", goBack = goBack) {
        SettingsCardTitle("账号安全", "修改成功后需要重新登录")
        SettingsFormTextField("当前密码", currentPassword, onCurrentChange, "请输入当前密码")
        SettingsFormTextField("新密码", newPassword, onNewChange, "请输入新密码")
        SettingsFormTextField("确认新密码", confirmPassword, onConfirmChange, "再次输入新密码")
        SettingsMessage(message)
        BlackCapsuleButton(text = if (submitting) "修改中" else "确认修改", modifier = Modifier.fillMaxWidth(), enabled = canSubmit, onClick = submit)
    }
}

@Composable
fun AccountDeletionScreen(
    confirmAccount: String,
    confirmDestroy: String,
    confirmWaiveRights: String,
    reason: String,
    submitting: Boolean,
    message: String?,
    onConfirmAccountChange: (String) -> Unit,
    onConfirmDestroyChange: (String) -> Unit,
    onConfirmWaiveRightsChange: (String) -> Unit,
    onReasonChange: (String) -> Unit,
    submit: () -> Unit,
    goBack: () -> Unit,
) {
    val canSubmit = confirmAccount.trim() == "我确认注销账号" &&
        confirmDestroy.trim() == "确认销毁" &&
        confirmWaiveRights.trim() == "确认清理远程连接数据" &&
        !submitting
    Box(Modifier.fillMaxSize()) {
        WhiteGlassBackground(Modifier.fillMaxSize())
        Column(
            Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp, vertical = 22.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            TopTitleBar(title = "注销账号", goBack = goBack)
            SettingsSectionCard {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    SettingsCardTitle("注销账号", "注销成功后账号不可恢复")
                    DeletionBullet("远程账号、登录令牌、设备、连接授权、协议确认和服务状态主数据会被删除。")
                    DeletionBullet("后台仅保留脱敏注销记录，以及注销前设备与连接状态快照用于审计与争议处理。")
                }
            }
            SettingsSectionCard {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    SettingsFormTextField("输入：我确认注销账号", confirmAccount, onConfirmAccountChange, "我确认注销账号")
                    SettingsFormTextField("输入：确认销毁", confirmDestroy, onConfirmDestroyChange, "确认销毁")
                    SettingsFormTextField("输入：确认清理远程连接数据", confirmWaiveRights, onConfirmWaiveRightsChange, "确认清理远程连接数据")
                    SettingsFormTextField("注销原因", reason, onReasonChange, "选填")
                    SettingsMessage(message)
                    SettingsDangerButton(text = if (submitting) "注销中" else "确认注销账号", enabled = canSubmit, onClick = submit)
                }
            }
        }
    }
}

@Composable
private fun SettingsFormScreen(title: String, goBack: () -> Unit, content: @Composable ColumnScope.() -> Unit) {
    Box(Modifier.fillMaxSize()) {
        WhiteGlassBackground(Modifier.fillMaxSize())
        Column(
            Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp, vertical = 22.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            TopTitleBar(title = title, goBack = goBack)
            SettingsSectionCard {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                    content = content,
                )
            }
        }
    }
}

@Composable
private fun SettingsFormTextField(label: String, value: String, onChange: (String) -> Unit, placeholder: String) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(label, color = AcodeColor.Muted, fontSize = 11.sp, fontWeight = FontWeight.SemiBold)
        TextField(
            value = value,
            onValueChange = onChange,
            placeholder = { Text(placeholder, color = AcodeColor.Muted.copy(alpha = 0.44f)) },
            textStyle = androidx.compose.ui.text.TextStyle(fontSize = 15.sp, color = AcodeColor.Ink),
            colors = TextFieldDefaults.colors(
                focusedContainerColor = Color.White.copy(alpha = 0.56f),
                unfocusedContainerColor = Color.White.copy(alpha = 0.56f),
                focusedIndicatorColor = Color.Transparent,
                unfocusedIndicatorColor = Color.Transparent,
            ),
            shape = RoundedCornerShape(16.dp),
            singleLine = true,
            modifier = Modifier
                .fillMaxWidth()
                .border(BorderStroke(1.dp, AcodeColor.GlassStroke), RoundedCornerShape(16.dp)),
        )
    }
}

@Composable
private fun SettingsSectionCard(
    modifier: Modifier = Modifier,
    content: @Composable BoxScope.() -> Unit,
) {
    val shape = RoundedCornerShape(26.dp)
    Box(
        modifier = modifier
            .fillMaxWidth()
            .shadow(16.dp, shape, ambientColor = Color.Black.copy(alpha = 0.055f), spotColor = Color.Black.copy(alpha = 0.055f))
            .clip(shape)
            .background(Color.White.copy(alpha = 0.62f))
            .border(BorderStroke(1.dp, Color.Black.copy(alpha = 0.055f)), shape),
        content = content,
    )
}

@Composable
private fun SettingsMenuRow(
    title: String,
    subtitle: String,
    icon: ImageVector,
    showChevron: Boolean = true,
    onClick: (() -> Unit)? = null,
) {
    SettingsBaseRow(
        title = title,
        subtitle = subtitle,
        icon = icon,
        tint = AcodeColor.Ink,
        showChevron = showChevron,
        onClick = onClick,
    )
}

@Composable
private fun SettingsActionRow(
    title: String,
    subtitle: String,
    icon: ImageVector,
    tint: Color,
    onClick: () -> Unit,
) {
    SettingsBaseRow(
        title = title,
        subtitle = subtitle,
        icon = icon,
        tint = tint,
        showChevron = false,
        onClick = onClick,
    )
}

@Composable
private fun SettingsBaseRow(
    title: String,
    subtitle: String,
    icon: ImageVector,
    tint: Color,
    showChevron: Boolean,
    onClick: (() -> Unit)?,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(horizontal = 14.dp, vertical = 13.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        SettingsPlainIcon(icon = icon, tint = tint.copy(alpha = 0.72f))
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, color = tint, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(subtitle, color = AcodeColor.Muted, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        if (showChevron) {
            Icon(
                imageVector = Icons.Rounded.ChevronRight,
                contentDescription = null,
                tint = AcodeColor.Muted.copy(alpha = 0.55f),
                modifier = Modifier.size(18.dp),
            )
        }
    }
}

@Composable
private fun SettingsPlainIcon(
    icon: ImageVector,
    tint: Color = AcodeColor.Ink.copy(alpha = 0.58f),
    size: androidx.compose.ui.unit.Dp = 16.dp,
    frame: androidx.compose.ui.unit.Dp = 31.dp,
) {
    Box(modifier = Modifier.size(frame), contentAlignment = Alignment.Center) {
        Icon(imageVector = icon, contentDescription = null, tint = tint, modifier = Modifier.size(size))
    }
}

@Composable
private fun SettingsCardTitle(title: String, subtitle: String) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp), modifier = Modifier.fillMaxWidth()) {
        Text(title, color = AcodeColor.Ink, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
        Text(subtitle, color = AcodeColor.Muted, fontSize = 11.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
private fun SettingsDivider(modifier: Modifier = Modifier) {
    HorizontalDivider(
        modifier = modifier
            .padding(start = 57.dp)
            .fillMaxWidth(),
        color = Color.Black.copy(alpha = 0.08f),
        thickness = 1.dp,
    )
}

@Composable
private fun SettingsMessage(message: String?) {
    if (!message.isNullOrBlank()) {
        Text(
            message,
            color = if (message.contains("成功") || message.contains("已")) AcodeColor.Muted else Color.Red.copy(alpha = 0.85f),
            fontSize = 12.sp,
            fontWeight = FontWeight.Medium,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 2.dp),
        )
    }
}

@Composable
private fun DeletionBullet(text: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.Top) {
        Text("!", color = Color.Red.copy(alpha = 0.78f), fontSize = 12.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 2.dp))
        Text(text, color = AcodeColor.Muted, fontSize = 12.sp, lineHeight = 18.sp, modifier = Modifier.weight(1f))
    }
}

@Composable
private fun SettingsDangerButton(text: String, enabled: Boolean, onClick: () -> Unit) {
    Button(
        onClick = onClick,
        enabled = enabled,
        modifier = Modifier
            .fillMaxWidth()
            .height(48.dp),
        colors = ButtonDefaults.buttonColors(
            containerColor = Color.Red,
            contentColor = Color.White,
            disabledContainerColor = Color.Red.copy(alpha = 0.42f),
            disabledContentColor = Color.White.copy(alpha = 0.72f),
        ),
        shape = RoundedCornerShape(17.dp),
        elevation = ButtonDefaults.buttonElevation(defaultElevation = 0.dp, pressedElevation = 0.dp),
    ) {
        Text(text, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
    }
}
