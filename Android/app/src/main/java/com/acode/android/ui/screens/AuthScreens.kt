package com.acode.android.ui.screens

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.ChevronLeft
import androidx.compose.material.icons.rounded.Code
import androidx.compose.material.icons.rounded.Email
import androidx.compose.material.icons.rounded.Lock
import androidx.compose.material.icons.rounded.Visibility
import androidx.compose.material.icons.rounded.VisibilityOff
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.acode.android.ui.components.AcodeIconButton
import com.acode.android.ui.components.WhiteGlassBackground
import com.acode.android.ui.theme.AcodeColor

@Composable
fun LoginScreen(
    email: String,
    password: String,
    agreed: Boolean,
    submitting: Boolean,
    message: String?,
    onEmailChange: (String) -> Unit,
    onPasswordChange: (String) -> Unit,
    toggleAgreement: () -> Unit,
    openRegister: () -> Unit,
    openForgot: () -> Unit,
    login: () -> Unit,
    openUserAgreement: () -> Unit = {},
    openPrivacyPolicy: () -> Unit = {},
) {
    val canSubmit = agreed && email.trim().isNotEmpty() && password.isNotEmpty() && !submitting
    AuthPageScaffold {
        Spacer(Modifier.weight(0.52f))
        AuthHeader(title = "欢迎回来", subtitle = "登录 AnnaCode，继续连接你的远程工作区")
        AuthLiquidCard {
            AuthLabel("邮箱")
            AuthInput(
                value = email,
                onValueChange = onEmailChange,
                placeholder = "请输入邮箱",
                icon = Icons.Rounded.Email,
            )
            AuthLabel("密码", modifier = Modifier.padding(top = 16.dp))
            AuthInput(
                value = password,
                onValueChange = onPasswordChange,
                placeholder = "请输入密码",
                icon = Icons.Rounded.Lock,
                trailingIcon = Icons.Rounded.Visibility,
                password = true,
            )
            AgreementRow(
                checked = agreed,
                onCheckedChange = toggleAgreement,
                openUserAgreement = openUserAgreement,
                openPrivacyPolicy = openPrivacyPolicy,
            )
            if (!message.isNullOrBlank()) {
                Text(
                    text = message,
                    color = authMessageColor(message),
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Medium,
                    modifier = Modifier.padding(bottom = 10.dp),
                )
            }
            AuthPrimaryButton(
                text = if (submitting) "登录中..." else "登录",
                loading = submitting,
                enabled = canSubmit,
                onClick = login,
            )
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 20.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                AuthTextButton("忘记密码", onClick = openForgot)
                AuthTextButton("创建账号", onClick = openRegister)
            }
        }
        Spacer(Modifier.weight(0.72f))
    }
}

@Composable
fun AuthCheckingScreen() {
    AuthPageScaffold {
        Spacer(Modifier.weight(1f))
        AuthHeader(title = "AnnaCode", subtitle = "正在检查登录状态")
        CircularProgressIndicator(
            modifier = Modifier.padding(top = 24.dp).size(26.dp),
            strokeWidth = 2.5.dp,
            color = AcodeColor.Ink,
        )
        Spacer(Modifier.weight(1f))
    }
}

@Composable
fun ForgotPasswordScreen(
    email: String,
    verificationCode: String,
    password: String,
    confirmPassword: String,
    submitting: Boolean,
    message: String?,
    onEmailChange: (String) -> Unit,
    onVerificationCodeChange: (String) -> Unit,
    onPasswordChange: (String) -> Unit,
    onConfirmPasswordChange: (String) -> Unit,
    requestCode: () -> Unit,
    goBack: () -> Unit,
    resetPassword: () -> Unit,
    codeSending: Boolean = false,
    codeCooldownSeconds: Int = 0,
) {
    val canSubmit = email.trim().isNotEmpty() &&
        verificationCode.trim().length >= 4 &&
        password.length >= 6 &&
        password == confirmPassword &&
        !submitting
    Box(Modifier.fillMaxSize()) {
        AuthPageScaffold {
            Spacer(Modifier.height(96.dp))
            AuthHeader(title = "忘记密码", subtitle = "通过邮箱验证码重置登录密码")
            AuthLiquidCard {
                AuthLabel("邮箱")
                AuthInput(
                    value = email,
                    onValueChange = onEmailChange,
                    placeholder = "请输入注册邮箱",
                    icon = Icons.Rounded.Email,
                )
                AuthLabel("邮箱验证码", modifier = Modifier.padding(top = 16.dp))
                AuthInput(
                    value = verificationCode,
                    onValueChange = onVerificationCodeChange,
                    placeholder = "6 位验证码",
                    icon = Icons.Rounded.Code,
                    keyboardType = KeyboardType.Number,
                    trailingText = codeButtonText(codeCooldownSeconds),
                    trailingLoading = codeSending,
                    trailingEnabled = !codeSending && codeCooldownSeconds <= 0,
                    trailingAction = requestCode,
                )
                AuthLabel("新密码", modifier = Modifier.padding(top = 16.dp))
                AuthInput(
                    value = password,
                    onValueChange = onPasswordChange,
                    placeholder = "设置新的登录密码",
                    icon = Icons.Rounded.Lock,
                    trailingIcon = Icons.Rounded.Visibility,
                    password = true,
                )
                AuthLabel("确认新密码", modifier = Modifier.padding(top = 16.dp))
                AuthInput(
                    value = confirmPassword,
                    onValueChange = onConfirmPasswordChange,
                    placeholder = "再次输入新密码",
                    icon = Icons.Rounded.Lock,
                    trailingIcon = Icons.Rounded.Visibility,
                    password = true,
                )
                if (!message.isNullOrBlank()) {
                    Text(
                        text = message,
                        color = authMessageColor(message),
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Medium,
                        modifier = Modifier.padding(top = 18.dp, bottom = 10.dp),
                    )
                } else {
                    Spacer(Modifier.height(18.dp))
                }
                AuthPrimaryButton(
                    text = if (submitting) "重置中..." else "重置密码",
                    loading = submitting,
                    enabled = canSubmit,
                    onClick = resetPassword,
                )
            }
            Spacer(Modifier.weight(1f))
        }
        AcodeIconButton(
            imageVector = Icons.Rounded.ChevronLeft,
            contentDescription = "返回",
            size = 44.dp,
            iconSize = 22.dp,
            modifier = Modifier
                .statusBarsPadding()
                .padding(start = 18.dp, top = 18.dp)
                .align(Alignment.TopStart),
            onClick = goBack,
        )
    }
}

@Composable
fun RegisterScreen(
    email: String,
    password: String,
    confirmPassword: String,
    verificationCode: String,
    agreed: Boolean,
    submitting: Boolean,
    message: String?,
    onEmailChange: (String) -> Unit,
    onPasswordChange: (String) -> Unit,
    onConfirmPasswordChange: (String) -> Unit,
    onVerificationCodeChange: (String) -> Unit,
    toggleAgreement: () -> Unit,
    requestCode: () -> Unit,
    goBack: () -> Unit,
    register: () -> Unit,
    codeSending: Boolean = false,
    codeCooldownSeconds: Int = 0,
    openUserAgreement: () -> Unit = {},
    openPrivacyPolicy: () -> Unit = {},
) {
    val canSubmit = agreed &&
        email.trim().isNotEmpty() &&
        verificationCode.trim().length >= 4 &&
        password.length >= 6 &&
        password == confirmPassword &&
        !submitting
    Box(Modifier.fillMaxSize()) {
        AuthPageScaffold {
            Spacer(Modifier.height(96.dp))
            AuthHeader(title = "创建账号", subtitle = "使用邮箱验证码完成账号创建")
            AuthLiquidCard {
                AuthLabel("邮箱")
                AuthInput(
                    value = email,
                    onValueChange = onEmailChange,
                    placeholder = "请输入邮箱",
                    icon = Icons.Rounded.Email,
                )
                AuthLabel("邮箱验证码", modifier = Modifier.padding(top = 16.dp))
                AuthInput(
                    value = verificationCode,
                    onValueChange = onVerificationCodeChange,
                    placeholder = "6 位验证码",
                    icon = Icons.Rounded.Code,
                    keyboardType = KeyboardType.Number,
                    trailingText = codeButtonText(codeCooldownSeconds),
                    trailingLoading = codeSending,
                    trailingEnabled = !codeSending && codeCooldownSeconds <= 0,
                    trailingAction = requestCode,
                )
                AuthLabel("密码", modifier = Modifier.padding(top = 16.dp))
                AuthInput(
                    value = password,
                    onValueChange = onPasswordChange,
                    placeholder = "设置登录密码",
                    icon = Icons.Rounded.Lock,
                    trailingIcon = Icons.Rounded.Visibility,
                    password = true,
                )
                AuthLabel("确认密码", modifier = Modifier.padding(top = 16.dp))
                AuthInput(
                    value = confirmPassword,
                    onValueChange = onConfirmPasswordChange,
                    placeholder = "再次输入密码",
                    icon = Icons.Rounded.Lock,
                    trailingIcon = Icons.Rounded.Visibility,
                    password = true,
                )
                AgreementRow(
                    checked = agreed,
                    onCheckedChange = toggleAgreement,
                    openUserAgreement = openUserAgreement,
                    openPrivacyPolicy = openPrivacyPolicy,
                )
                if (!message.isNullOrBlank()) {
                    Text(
                        text = message,
                        color = authMessageColor(message),
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Medium,
                        modifier = Modifier.padding(bottom = 10.dp),
                    )
                }
                AuthPrimaryButton(
                    text = if (submitting) "注册中..." else "注册并登录",
                    loading = submitting,
                    enabled = canSubmit,
                    onClick = register,
                )
            }
            Spacer(Modifier.weight(1f))
        }
        AcodeIconButton(
            imageVector = Icons.Rounded.ChevronLeft,
            contentDescription = "返回",
            size = 44.dp,
            iconSize = 22.dp,
            modifier = Modifier
                .statusBarsPadding()
                .padding(start = 18.dp, top = 18.dp)
                .align(Alignment.TopStart),
            onClick = goBack,
        )
    }
}

@Composable
private fun AuthPageScaffold(content: @Composable ColumnScope.() -> Unit) {
    Box(Modifier.fillMaxSize()) {
        WhiteGlassBackground(Modifier.fillMaxSize())
        Box(
            modifier = Modifier
                .size(240.dp)
                .offset(x = (-70).dp, y = (-80).dp)
                .blur(34.dp)
                .clip(CircleShape)
                .background(Color.White.copy(alpha = 0.98f)),
        )
        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .navigationBarsPadding()
                .imePadding()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 18.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            content = content,
        )
    }
}

@Composable
private fun AuthHeader(title: String, subtitle: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Box(
            modifier = Modifier
                .size(66.dp)
                .shadow(12.dp, RoundedCornerShape(18.dp), ambientColor = Color.Black.copy(0.12f), spotColor = Color.Black.copy(0.12f))
                .clip(RoundedCornerShape(18.dp))
                .background(Color.White)
                .border(BorderStroke(0.8.dp, Color.White.copy(alpha = 0.7f)), RoundedCornerShape(18.dp)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Rounded.Code, contentDescription = null, tint = AcodeColor.Ink, modifier = Modifier.size(42.dp))
        }
        Text(
            text = title,
            color = AcodeColor.Ink,
            fontSize = 28.sp,
            fontWeight = FontWeight.SemiBold,
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(top = 12.dp),
        )
        Text(
            text = subtitle,
            color = AcodeColor.Muted,
            fontSize = 14.sp,
            fontWeight = FontWeight.Normal,
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(top = 5.dp, bottom = 24.dp),
        )
    }
}

@Composable
private fun AuthLiquidCard(content: @Composable ColumnScope.() -> Unit) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .widthIn(max = 430.dp)
            .shadow(22.dp, RoundedCornerShape(30.dp), ambientColor = Color.Black.copy(0.06f), spotColor = Color.Black.copy(0.06f))
            .clip(RoundedCornerShape(30.dp))
            .background(Color.White.copy(alpha = 0.68f))
            .border(BorderStroke(0.8.dp, Color.White.copy(alpha = 0.88f)), RoundedCornerShape(30.dp))
            .padding(18.dp),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(0.dp), content = content)
    }
}

@Composable
private fun AuthLabel(text: String, modifier: Modifier = Modifier) {
    Text(
        text = text,
        color = AcodeColor.Muted,
        fontSize = 12.sp,
        fontWeight = FontWeight.Medium,
        modifier = modifier.padding(start = 0.dp, bottom = 7.dp),
    )
}

@Composable
private fun AuthInput(
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String,
    icon: ImageVector,
    modifier: Modifier = Modifier,
    trailingIcon: ImageVector? = null,
    trailingText: String? = null,
    trailingLoading: Boolean = false,
    trailingEnabled: Boolean = true,
    trailingAction: (() -> Unit)? = null,
    password: Boolean = false,
    keyboardType: KeyboardType = KeyboardType.Text,
) {
    var passwordVisible by remember { mutableStateOf(false) }
    val shape = RoundedCornerShape(18.dp)
    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(52.dp)
            .shadow(16.dp, shape, ambientColor = Color.Black.copy(0.10f), spotColor = Color.Black.copy(0.10f))
            .clip(shape)
            .background(Color.White.copy(alpha = 0.68f))
            .border(BorderStroke(0.8.dp, Color.White.copy(alpha = 0.88f)), shape),
    ) {
        Row(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Icon(icon, contentDescription = null, tint = AcodeColor.Muted, modifier = Modifier.size(18.dp))
            Box(modifier = Modifier.weight(1f), contentAlignment = Alignment.CenterStart) {
                if (value.isEmpty() && placeholder.isNotEmpty()) {
                    Text(placeholder, color = AcodeColor.Muted.copy(alpha = 0.34f), fontSize = 15.sp, fontWeight = FontWeight.Medium)
                }
                BasicTextField(
                    value = value,
                    onValueChange = onValueChange,
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = if (password) KeyboardType.Password else keyboardType),
                    visualTransformation = if (password && !passwordVisible) PasswordVisualTransformation() else VisualTransformation.None,
                    cursorBrush = SolidColor(AcodeColor.Ink),
                    textStyle = TextStyle(
                        color = AcodeColor.Ink,
                        fontSize = 15.sp,
                        fontWeight = FontWeight.Medium,
                    ),
                    modifier = Modifier.fillMaxWidth(),
                )
            }
            if (trailingIcon != null) {
                val iconToShow = if (password && passwordVisible) Icons.Rounded.VisibilityOff else trailingIcon
                Icon(
                    iconToShow,
                    contentDescription = null,
                    tint = AcodeColor.Muted,
                    modifier = Modifier
                        .size(18.dp)
                        .clip(CircleShape)
                        .clickable(
                            enabled = password,
                            indication = null,
                            interactionSource = remember { MutableInteractionSource() },
                        ) { passwordVisible = !passwordVisible },
                )
            }
            if (trailingText != null) {
                val trailingActionEnabled = trailingEnabled && trailingAction != null
                Box(
                    modifier = Modifier
                        .defaultMinSize(minWidth = 58.dp, minHeight = 34.dp)
                        .clip(CircleShape)
                        .background(Color.White.copy(alpha = if (trailingActionEnabled) 1f else 0.72f))
                        .clickable(
                            enabled = trailingActionEnabled,
                            indication = null,
                            interactionSource = remember { MutableInteractionSource() },
                        ) { trailingAction?.invoke() }
                        .padding(horizontal = 4.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    if (trailingLoading) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(14.dp),
                            strokeWidth = 2.dp,
                            color = AcodeColor.Ink.copy(alpha = 0.82f),
                        )
                    } else {
                        Text(
                            text = trailingText,
                            color = if (trailingActionEnabled) AcodeColor.Ink else AcodeColor.Muted.copy(alpha = 0.7f),
                            fontSize = 13.sp,
                            fontWeight = FontWeight.SemiBold,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun AgreementRow(
    checked: Boolean,
    onCheckedChange: () -> Unit,
    openUserAgreement: () -> Unit,
    openPrivacyPolicy: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 24.dp, bottom = 18.dp),
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(9.dp),
    ) {
        Box(
            modifier = Modifier
                .size(17.dp)
                .padding(top = 1.dp)
                .clip(CircleShape)
                .background(if (checked) AcodeColor.Ink else Color.Transparent)
                .border(BorderStroke(1.3.dp, if (checked) AcodeColor.Ink else AcodeColor.Muted.copy(alpha = 0.65f)), CircleShape)
                .clickable(
                    indication = null,
                    interactionSource = remember { MutableInteractionSource() },
                    onClick = onCheckedChange,
                ),
            contentAlignment = Alignment.Center,
        ) {
            if (checked) {
                Icon(Icons.Rounded.Check, contentDescription = null, tint = Color.White, modifier = Modifier.size(12.dp))
            }
        }
        Row(modifier = Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically) {
            Text(
                "我已阅读并同意",
                color = AcodeColor.Muted,
                fontSize = 12.sp,
                fontWeight = FontWeight.Medium,
                modifier = Modifier
                    .clip(RoundedCornerShape(6.dp))
                    .clickable(
                        indication = null,
                        interactionSource = remember { MutableInteractionSource() },
                        onClick = onCheckedChange,
                    ),
            )
            AuthInlineLink("用户协议", onClick = openUserAgreement)
            Text("和", color = AcodeColor.Muted, fontSize = 12.sp, fontWeight = FontWeight.Medium)
            AuthInlineLink("隐私政策", onClick = openPrivacyPolicy)
        }
    }
}

@Composable
private fun AuthInlineLink(text: String, onClick: () -> Unit) {
    Text(
        text = text,
        color = AcodeColor.Ink.copy(alpha = 0.82f),
        fontSize = 12.sp,
        fontWeight = FontWeight.Medium,
        modifier = Modifier
            .clip(RoundedCornerShape(6.dp))
            .clickable(
                indication = null,
                interactionSource = remember { MutableInteractionSource() },
                onClick = onClick,
            ),
    )
}

private fun codeButtonText(cooldownSeconds: Int): String =
    if (cooldownSeconds > 0) "${cooldownSeconds}s" else "获取"

private fun authMessageColor(message: String): Color =
    if (message.contains("已")) AcodeColor.Muted else Color.Red.copy(alpha = 0.92f)

@Composable
private fun AuthPrimaryButton(
    text: String,
    loading: Boolean,
    enabled: Boolean,
    onClick: () -> Unit,
) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(52.dp)
            .clip(RoundedCornerShape(26.dp))
            .background(AcodeColor.Ink.copy(alpha = if (enabled) 1f else 0.55f))
            .clickable(
                enabled = enabled,
                indication = null,
                interactionSource = remember { MutableInteractionSource() },
                onClick = onClick,
            ),
        contentAlignment = Alignment.Center,
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            if (loading) {
                CircularProgressIndicator(
                    modifier = Modifier.size(16.dp),
                    strokeWidth = 2.dp,
                    color = Color.White,
                )
            }
            Text(
                text,
                color = Color.White.copy(alpha = if (enabled) 1f else 0.72f),
                fontSize = 15.sp,
                fontWeight = FontWeight.SemiBold,
            )
        }
    }
}

@Composable
private fun AuthTextButton(text: String, onClick: () -> Unit) {
    Text(
        text = text,
        color = AcodeColor.Ink,
        fontSize = 14.sp,
        fontWeight = FontWeight.SemiBold,
        modifier = Modifier
            .clip(RoundedCornerShape(12.dp))
            .clickable(onClick = onClick)
            .padding(vertical = 4.dp),
    )
}
