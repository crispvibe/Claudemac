package com.codevoke.android.ui.screens

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
import com.codevoke.android.ui.state.CodevokeViewModel
import com.codevoke.android.ui.state.AuthGateState

private enum class CodevokeScreen {
    Login,
    Register,
    Chat,
    Devices,
    Settings,
    Account,
    DeleteAccount,
    Legal,
}

@Composable
fun CodevokeApp() {
    val vm: CodevokeViewModel = viewModel()
    val lifecycleOwner = LocalLifecycleOwner.current
    var screen by remember { mutableStateOf(CodevokeScreen.Login) }
    val backStack = remember { mutableStateListOf<CodevokeScreen>() }

    fun replaceScreen(next: CodevokeScreen) {
        backStack.clear()
        screen = next
    }

    fun navigateTo(next: CodevokeScreen) {
        if (next == screen) return
        backStack.add(screen)
        screen = next
    }

    fun navigateBack(fallback: CodevokeScreen) {
        screen = if (backStack.isNotEmpty()) {
            backStack.removeAt(backStack.lastIndex)
        } else {
            fallback
        }
    }

    fun handleBack() {
        when (screen) {
            CodevokeScreen.Login -> Unit
            CodevokeScreen.Register,
            CodevokeScreen.Forgot -> navigateBack(CodevokeScreen.Login)
            CodevokeScreen.Chat -> Unit
            CodevokeScreen.Devices,
            CodevokeScreen.Settings -> navigateBack(CodevokeScreen.Chat)
            CodevokeScreen.Account,
            CodevokeScreen.Legal -> navigateBack(CodevokeScreen.Settings)
            CodevokeScreen.ChangePassword,
            CodevokeScreen.DeleteAccount -> navigateBack(CodevokeScreen.Account)
        }
    }

    LaunchedEffect(vm.auth.gateState) {
        if (vm.auth.gateState == AuthGateState.Authenticated && screen == CodevokeScreen.Login) {
            replaceScreen(CodevokeScreen.Chat)
        }
    }

    LaunchedEffect(screen, vm.auth.gateState) {
        if (screen == CodevokeScreen.Devices && vm.auth.gateState == AuthGateState.Authenticated) {
            vm.loadRemoteDevices()
        }
    }

    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_START) vm.resumeFromForeground()
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    BackHandler(enabled = screen != CodevokeScreen.Login && screen != CodevokeScreen.Chat, onBack = ::handleBack)

    when (screen) {
        CodevokeScreen.Login -> if (vm.auth.gateState == AuthGateState.Checking) AuthCheckingScreen() else LoginScreen(
            email = vm.auth.email,
            verificationCode = vm.auth.verificationCode,
            agreed = vm.auth.agreed,
            submitting = vm.auth.submitting,
            message = vm.auth.message,
            onEmailChange = vm::updateEmail,
            onVerificationCodeChange = vm::updateVerificationCode,
            toggleAgreement = vm::toggleAgreement,
            openRegister = { navigateTo(CodevokeScreen.Register) },
            requestCode = vm::requestLoginCode,
            login = { vm.requestLogin { replaceScreen(CodevokeScreen.Chat) } },
            codeSending = vm.auth.loginCodeSending,
            codeCooldownSeconds = vm.auth.loginCodeCooldown,
            openUserAgreement = {
                vm.presentLegal("user_agreement")
                navigateTo(CodevokeScreen.Legal)
            },
            openPrivacyPolicy = {
                vm.presentLegal("privacy_policy")
                navigateTo(CodevokeScreen.Legal)
            },
        )
        CodevokeScreen.Register -> RegisterScreen(
            email = vm.auth.email,
            verificationCode = vm.auth.verificationCode,
            agreed = vm.auth.agreed,
            submitting = vm.auth.submitting,
            message = vm.auth.message,
            onEmailChange = vm::updateEmail,
            onVerificationCodeChange = vm::updateVerificationCode,
            toggleAgreement = vm::toggleAgreement,
            requestCode = vm::requestRegisterCode,
            goBack = { navigateBack(CodevokeScreen.Login) },
            register = { vm.requestRegister { replaceScreen(CodevokeScreen.Chat) } },
            codeSending = vm.auth.registerCodeSending,
            codeCooldownSeconds = vm.auth.registerCodeCooldown,
            openUserAgreement = {
                vm.presentLegal("user_agreement")
                navigateTo(CodevokeScreen.Legal)
            },
            openPrivacyPolicy = {
                vm.presentLegal("privacy_policy")
                navigateTo(CodevokeScreen.Legal)
            },
        )
        CodevokeScreen.Chat -> ChatScreen(
            connectionStatus = vm.chat.connectionStatus,
            runtimeStatus = vm.chat.runtimeStatus,
            transportLabel = vm.transportLabel,
            topTitle = vm.chat.selectedProject?.name ?: "Codevoke",
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
            openSettings = { navigateTo(CodevokeScreen.Settings) },
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
        CodevokeScreen.Devices -> DeviceListScreen(
            devices = vm.devices.devices,
            loading = vm.devices.loading,
            deviceCode = vm.devices.deviceCode,
            resolving = vm.devices.resolvingCode,
            connecting = vm.devices.connecting,
            resolvedDevice = vm.devices.resolvedDevice,
            message = vm.devices.message,
            connectedDeviceId = vm.devices.connectedDeviceId,
            connectedTransport = vm.devices.connectedTransport,
            goBack = { navigateBack(CodevokeScreen.Chat) },
            refresh = vm::loadRemoteDevices,
            connect = { device -> vm.connectRemoteDevice(device) { replaceScreen(CodevokeScreen.Chat) } },
            onCodeChange = vm::updateDeviceCode,
            resolve = vm::resolveDeviceCode,
            connectResolved = { vm.connectResolvedDevice { replaceScreen(CodevokeScreen.Chat) } },
        )
        CodevokeScreen.Settings -> SettingsScreen(
            account = vm.auth.account,
            connectionStatus = vm.chat.connectionStatus,
            selectedCLI = vm.chat.composer.cli,
            goBack = { navigateBack(CodevokeScreen.Chat) },
            openAccount = { navigateTo(CodevokeScreen.Account) },
            openDevices = { navigateTo(CodevokeScreen.Devices) },
            openLegal = { navigateTo(CodevokeScreen.Legal) },
        )
        CodevokeScreen.Account -> AccountSecurityScreen(
            account = vm.auth.account,
            message = vm.auth.message,
            goBack = { navigateBack(CodevokeScreen.Settings) },
            openDeleteAccount = { navigateTo(CodevokeScreen.DeleteAccount) },
            logout = {
                vm.logout()
                replaceScreen(CodevokeScreen.Login)
            },
        )
        CodevokeScreen.DeleteAccount -> AccountDeletionScreen(
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
            submit = { vm.deleteAccount { replaceScreen(CodevokeScreen.Login) } },
            goBack = { navigateBack(CodevokeScreen.Account) },
        )
        CodevokeScreen.Legal -> LegalScreen(
            documents = vm.auth.legalDocuments,
            goBack = { navigateBack(CodevokeScreen.Settings) },
        )
    }
}
