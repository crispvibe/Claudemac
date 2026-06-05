package com.acode.android.ui.screens

import androidx.activity.compose.BackHandler
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.viewmodel.compose.viewModel
import com.acode.android.ui.state.AcodeViewModel
import com.acode.android.ui.state.AuthGateState

private enum class AcodeScreen {
    Login,
    Register,
    Forgot,
    Chat,
    Devices,
    Settings,
    Account,
    ChangePassword,
    DeleteAccount,
    Legal,
}

@Composable
fun AcodeApp() {
    val vm: AcodeViewModel = viewModel()
    val lifecycleOwner = LocalLifecycleOwner.current
    var screen by remember { mutableStateOf(AcodeScreen.Login) }
    val backStack = remember { mutableStateListOf<AcodeScreen>() }

    fun replaceScreen(next: AcodeScreen) {
        backStack.clear()
        screen = next
    }

    fun navigateTo(next: AcodeScreen) {
        if (next == screen) return
        backStack.add(screen)
        screen = next
    }

    fun navigateBack(fallback: AcodeScreen) {
        screen = if (backStack.isNotEmpty()) {
            backStack.removeAt(backStack.lastIndex)
        } else {
            fallback
        }
    }

    fun handleBack() {
        when (screen) {
            AcodeScreen.Login -> Unit
            AcodeScreen.Register,
            AcodeScreen.Forgot -> navigateBack(AcodeScreen.Login)
            AcodeScreen.Chat -> Unit
            AcodeScreen.Devices,
            AcodeScreen.Settings -> navigateBack(AcodeScreen.Chat)
            AcodeScreen.Account,
            AcodeScreen.Legal -> navigateBack(AcodeScreen.Settings)
            AcodeScreen.ChangePassword,
            AcodeScreen.DeleteAccount -> navigateBack(AcodeScreen.Account)
        }
    }

    LaunchedEffect(vm.auth.gateState) {
        if (vm.auth.gateState == AuthGateState.Authenticated && screen == AcodeScreen.Login) {
            replaceScreen(AcodeScreen.Chat)
        }
    }

    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_START) vm.resumeFromForeground()
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    BackHandler(enabled = screen != AcodeScreen.Login && screen != AcodeScreen.Chat, onBack = ::handleBack)

    when (screen) {
        AcodeScreen.Login -> if (vm.auth.gateState == AuthGateState.Checking) AuthCheckingScreen() else LoginScreen(
            email = vm.auth.email,
            password = vm.auth.password,
            agreed = vm.auth.agreed,
            submitting = vm.auth.submitting,
            message = vm.auth.message,
            onEmailChange = vm::updateEmail,
            onPasswordChange = vm::updatePassword,
            toggleAgreement = vm::toggleAgreement,
            openRegister = { navigateTo(AcodeScreen.Register) },
            openForgot = { navigateTo(AcodeScreen.Forgot) },
            login = { vm.requestLogin { replaceScreen(AcodeScreen.Chat) } },
            openUserAgreement = {
                vm.presentLegal("user_agreement")
                navigateTo(AcodeScreen.Legal)
            },
            openPrivacyPolicy = {
                vm.presentLegal("privacy_policy")
                navigateTo(AcodeScreen.Legal)
            },
        )
        AcodeScreen.Register -> RegisterScreen(
            email = vm.auth.email,
            password = vm.auth.password,
            confirmPassword = vm.auth.confirmPassword,
            verificationCode = vm.auth.verificationCode,
            agreed = vm.auth.agreed,
            submitting = vm.auth.submitting,
            message = vm.auth.message,
            onEmailChange = vm::updateEmail,
            onPasswordChange = vm::updatePassword,
            onConfirmPasswordChange = vm::updateConfirmPassword,
            onVerificationCodeChange = vm::updateVerificationCode,
            toggleAgreement = vm::toggleAgreement,
            requestCode = vm::requestRegisterCode,
            goBack = { navigateBack(AcodeScreen.Login) },
            register = { vm.requestRegister { replaceScreen(AcodeScreen.Chat) } },
            codeSending = vm.auth.registerCodeSending,
            codeCooldownSeconds = vm.auth.registerCodeCooldown,
            openUserAgreement = {
                vm.presentLegal("user_agreement")
                navigateTo(AcodeScreen.Legal)
            },
            openPrivacyPolicy = {
                vm.presentLegal("privacy_policy")
                navigateTo(AcodeScreen.Legal)
            },
        )
        AcodeScreen.Forgot -> ForgotPasswordScreen(
            email = vm.auth.email,
            verificationCode = vm.auth.verificationCode,
            password = vm.auth.forgotPassword,
            confirmPassword = vm.auth.forgotConfirmPassword,
            submitting = vm.auth.submitting,
            message = vm.auth.message,
            onEmailChange = vm::updateEmail,
            onVerificationCodeChange = vm::updateVerificationCode,
            onPasswordChange = vm::updateForgotPassword,
            onConfirmPasswordChange = vm::updateForgotConfirmPassword,
            requestCode = vm::requestPasswordResetCode,
            goBack = { navigateBack(AcodeScreen.Login) },
            resetPassword = { vm.requestPasswordReset { replaceScreen(AcodeScreen.Login) } },
            codeSending = vm.auth.passwordResetCodeSending,
            codeCooldownSeconds = vm.auth.passwordResetCodeCooldown,
        )
        AcodeScreen.Chat -> ChatScreen(
            connectionStatus = vm.chat.connectionStatus,
            runtimeStatus = vm.chat.runtimeStatus,
            topTitle = vm.chat.selectedProject?.name ?: "Acode",
            messages = vm.chat.messages,
            streamingTexts = vm.chat.streamingTexts,
            projects = vm.chat.projects,
            models = vm.chat.models,
            sessions = vm.chat.filteredSessions,
            files = vm.chat.files,
            lastError = vm.chat.lastError,
            fileError = vm.chat.fileError,
            isRefreshing = vm.chat.isRefreshing,
            isLoadingHistory = vm.chat.isLoadingHistory,
            isAwaitingFirstModelOutput = vm.chat.isAwaitingFirstModelOutput,
            isLoadingFiles = vm.chat.isLoadingFiles,
            attachments = vm.chat.attachments,
            isUploadingAttachment = vm.chat.isUploadingAttachment,
            currentFilePath = vm.chat.currentFilePath,
            parentFilePath = vm.chat.parentFilePath,
            selectedProjectId = vm.chat.selectedProjectId,
            selectedSessionId = vm.chat.selectedSessionId,
            selectedModelId = vm.chat.selectedModelId,
            composer = vm.chat.composer,
            queuedRequests = vm.chat.queuedRequests,
            openSettings = { navigateTo(AcodeScreen.Settings) },
            refresh = vm::refreshChat,
            selectProject = vm::selectProject,
            selectModel = vm::selectModel,
            selectSession = vm::selectSession,
            newChat = vm::startNewChat,
            inputText = vm.chat.inputText,
            updateInput = vm::updateInput,
            sendMessage = vm::sendCurrentMessage,
            stopGeneration = vm::stopGeneration,
            uploadAttachment = vm::uploadAttachment,
            removeAttachment = vm::removeAttachment,
            setCLI = vm::setCLI,
            setPermissionMode = vm::setPermissionMode,
            setReasoningEffort = vm::setReasoningEffort,
            cancelQueued = vm::cancelQueued,
            flushQueue = vm::flushQueue,
            editQueued = vm::editQueued,
            respondPermission = vm::respondPermission,
            respondInteractive = vm::respondInteractive,
            requestSnapshot = { vm.requestSnapshot() },
            insertPath = vm::insertPath,
            openFile = vm::openFile,
            openParentDirectory = vm::openParentDirectory,
        )
        AcodeScreen.Devices -> DeviceListScreen(
            devices = vm.devices.devices,
            loading = vm.devices.loading,
            deviceCode = vm.devices.deviceCode,
            resolving = vm.devices.resolvingCode,
            connecting = vm.devices.connecting,
            resolvedDevice = vm.devices.resolvedDevice,
            message = vm.devices.message,
            goBack = { navigateBack(AcodeScreen.Chat) },
            refresh = vm::loadRemoteDevices,
            connect = { device -> vm.connectRemoteDevice(device) { replaceScreen(AcodeScreen.Chat) } },
            onCodeChange = vm::updateDeviceCode,
            resolve = vm::resolveDeviceCode,
            connectResolved = { vm.connectResolvedDevice { replaceScreen(AcodeScreen.Chat) } },
        )
        AcodeScreen.Settings -> SettingsScreen(
            account = vm.auth.account,
            connectionStatus = vm.chat.connectionStatus,
            selectedCLI = vm.chat.composer.cli,
            goBack = { navigateBack(AcodeScreen.Chat) },
            openAccount = { navigateTo(AcodeScreen.Account) },
            openDevices = { navigateTo(AcodeScreen.Devices) },
            openLegal = { navigateTo(AcodeScreen.Legal) },
        )
        AcodeScreen.Account -> AccountSecurityScreen(
            account = vm.auth.account,
            message = vm.auth.message,
            goBack = { navigateBack(AcodeScreen.Settings) },
            openChangePassword = { navigateTo(AcodeScreen.ChangePassword) },
            openDeleteAccount = { navigateTo(AcodeScreen.DeleteAccount) },
            logout = {
                vm.logout()
                replaceScreen(AcodeScreen.Login)
            },
        )
        AcodeScreen.ChangePassword -> ChangePasswordScreen(
            currentPassword = vm.auth.currentPassword,
            newPassword = vm.auth.newPassword,
            confirmPassword = vm.auth.newPasswordConfirm,
            submitting = vm.auth.submitting,
            message = vm.auth.message,
            onCurrentChange = vm::updateCurrentPassword,
            onNewChange = vm::updateNewPassword,
            onConfirmChange = vm::updateNewPasswordConfirm,
            submit = { vm.changePassword { replaceScreen(AcodeScreen.Login) } },
            goBack = { navigateBack(AcodeScreen.Account) },
        )
        AcodeScreen.DeleteAccount -> AccountDeletionScreen(
            confirmAccount = vm.auth.deletionConfirmAccount,
            confirmDestroy = vm.auth.deletionConfirmDestroy,
            confirmWaiveRights = vm.auth.deletionConfirmWaiveRights,
            reason = vm.auth.deletionReason,
            submitting = vm.auth.submitting,
            message = vm.auth.message,
            onConfirmAccountChange = vm::updateDeletionConfirmAccount,
            onConfirmDestroyChange = vm::updateDeletionConfirmDestroy,
            onConfirmWaiveRightsChange = vm::updateDeletionConfirmWaiveRights,
            onReasonChange = vm::updateDeletionReason,
            submit = { vm.deleteAccount { replaceScreen(AcodeScreen.Login) } },
            goBack = { navigateBack(AcodeScreen.Account) },
        )
        AcodeScreen.Legal -> LegalScreen(
            documents = vm.auth.legalDocuments,
            goBack = { navigateBack(AcodeScreen.Settings) },
        )
    }
}
