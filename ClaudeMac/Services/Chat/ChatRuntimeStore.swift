import Combine
import Foundation

@MainActor
final class ChatRuntimeStore: ObservableObject {
    private var statesByKey: [String: ChatPanelState] = [:]
    private var cancellablesByState: [ObjectIdentifier: AnyCancellable] = [:]
    @Published private var activityBySessionID: [String: ChatSessionActivity] = [:]

    init() {
        refreshPersistedActivities()
    }

    func state(
        for appState: AppState,
        modelID: String,
        permissionMode: ChatPermissionMode,
        reasoningEffort: ChatReasoningEffort
    ) -> ChatPanelState {
        let key = runtimeKey(for: appState)
        if let localKey = localHistoryKey(for: appState), let state = statesByKey[localKey] {
            statesByKey[key] = state
            return state
        }
        if let state = statesByKey[key] {
            return state
        }

        let state = ChatPanelState()
        bind(state, primaryHistoryID: appState.selectedCLIHistoryID, appState: appState)
        state.loadFromAppState(appState, modelID: modelID, permissionMode: permissionMode, reasoningEffort: reasoningEffort)
        statesByKey[key] = state
        registerAliases(for: state, primaryHistoryID: appState.selectedCLIHistoryID)
        return state
    }

    func activity(for session: CLIHistorySession) -> ChatSessionActivity? {
        activityBySessionID[session.id]
    }

    func refreshPersistedActivities() {
        var activities = activityBySessionID
        for session in ChatSessionStore.loadSessions() {
            activities[historyID(for: session)] = ChatSessionActivity(
                status: session.runStatus,
                statusText: session.statusText,
                queuedCount: session.queuedRequests.count,
                lastCompletedAt: session.lastCompletedAt,
                activeRunStartedAt: session.activeRunStartedAt
            )
        }
        activityBySessionID = activities
    }

    func removeRuntime(for session: CLIHistorySession) {
        activityBySessionID.removeValue(forKey: session.id)
        statesByKey.removeValue(forKey: "history:\(session.id)")
        if session.storageKey == ChatSessionStore.storageKey {
            statesByKey.removeValue(forKey: "local:\(session.sessionId)")
        }
    }

    private func bind(_ state: ChatPanelState, primaryHistoryID: String?, appState: AppState) {
        state.onActivityChanged = { [weak self, weak state] activity in
            guard let self, let state else { return }
            self.updateActivity(activity, for: state, primaryHistoryID: primaryHistoryID)
        }
        state.onSessionPersisted = { [weak self, weak state, weak appState] in
            guard let self, let state else { return }
            self.registerAliases(for: state, primaryHistoryID: primaryHistoryID)
            self.refreshPersistedActivities()
            appState?.refreshCLIHistory()
        }
        let identifier = ObjectIdentifier(state)
        cancellablesByState[identifier] = state.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    private func updateActivity(_ activity: ChatSessionActivity?, for state: ChatPanelState, primaryHistoryID: String?) {
        if let primaryHistoryID, let activity {
            activityBySessionID[primaryHistoryID] = activity
        }
        guard let session = state.currentSessionSnapshot, let activity else { return }
        activityBySessionID[historyID(for: session)] = activity
    }

    private func registerAliases(for state: ChatPanelState, primaryHistoryID: String?) {
        guard let session = state.currentSessionSnapshot else { return }
        let localKey = "local:\(session.id.uuidString)"
        statesByKey[localKey] = state
        if let primaryHistoryID {
            statesByKey["history:\(primaryHistoryID)"] = state
        }
    }

    private func runtimeKey(for appState: AppState) -> String {
        if let historyID = appState.selectedCLIHistoryID {
            return "history:\(historyID)"
        }
        let projectID = appState.selectedProjectID?.uuidString ?? "none"
        return "draft:\(projectID):\(appState.chatConversationSerial.uuidString)"
    }

    private func localHistoryKey(for appState: AppState) -> String? {
        guard let historyID = appState.selectedCLIHistoryID,
              let history = appState.cliHistory.first(where: { $0.id == historyID }),
              history.storageKey == ChatSessionStore.storageKey else { return nil }
        return "local:\(history.sessionId)"
    }

    private func historyID(for session: ChatSessionRecord) -> String {
        "\(session.cli.rawValue):\(session.id.uuidString)"
    }
}
