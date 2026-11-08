#if targetEnvironment(macCatalyst)
import BridgeCore
import OSLog
import UIKit

/// One process-wide presentation shared by the repository and its transient scene.
@MainActor
final class WindowPresence {
    static let shared = WindowPresence()
    let activity = CommandActivity()
    private let logger = Logger(subsystem: "org.homekitrestbridge.app", category: "WindowPresence")
    private var pendingCreation: UUID?
    private weak var commandScene: UIWindowScene?
    private var closingSessionID: String?
    private var dismissal: Task<Void, Never>?
    private lazy var recovery = ForegroundRecoveryCoordinator(
        isReady: { [weak self] in self?.isReady == true },
        restore: { [weak self] in await self?.presentCommandWindow() ?? false }
    )

    private init() {}

    func beginCommand(title: String, detail: String) async throws -> UUID? {
        try Task.checkCancellation()
        // An open main window already provides HomeKit access. Preserve it as-is.
        if hasForegroundMainWindow && commandSession == nil && pendingCreation == nil { return nil }
        dismissal?.cancel()
        let id = activity.begin(title: title, detail: detail)
        do {
            guard try await recovery.ensureReady() else {
                throw APIError(code: "window_required", message: "HKRelay could not show the command window. Open HKRelay from the menu bar and retry.")
            }
            return id
        } catch {
            endCommand(id, failed: true)
            throw error
        }
    }

    func endCommand(_ id: UUID?, failed: Bool) {
        guard let id else { return }
        activity.finish(id, failed: failed)
        scheduleDismissal()
    }

    func commandSceneConnected(_ scene: UIWindowScene) {
        commandScene = scene
        pendingCreation = nil
        logger.notice("Transient command window connected.")
        scheduleDismissal()
    }

    func commandSceneDisconnected(_ session: UISceneSession) {
        if commandScene?.session.persistentIdentifier == session.persistentIdentifier { commandScene = nil }
        if closingSessionID == session.persistentIdentifier { closingSessionID = nil }
        logger.notice("Transient command window closed.")
        logger.notice("Foreground main windows after dismissal: \(self.windowScenes.filter { !self.isCommand($0.session) && self.isForeground($0) }.count).")
    }

    private var windowScenes: [UIWindowScene] {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .filter { $0.session.role == .windowApplication && !$0.windows.isEmpty }
    }

    private func isCommand(_ session: UISceneSession) -> Bool {
        session.scene?.delegate is CommandSceneDelegate ||
            session.configuration.name == CommandSceneDelegate.configurationName
    }

    private var commandSession: UISceneSession? {
        commandScene?.session ?? UIApplication.shared.openSessions.first(where: isCommand)
    }

    private var hasForegroundMainWindow: Bool {
        windowScenes.contains { !isCommand($0.session) && isForeground($0) }
    }

    private var isReady: Bool {
        closingSessionID == nil && windowScenes.contains(where: isForeground)
    }

    private func isForeground(_ scene: UIWindowScene) -> Bool {
        scene.activationState == .foregroundActive || scene.activationState == .foregroundInactive
    }

    private func presentCommandWindow() async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        // Wait for an already-closing card to disconnect before creating its replacement.
        while closingSessionID != nil && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard closingSessionID == nil else { return false }
        if isReady { return true }

        let userActivity = NSUserActivity(activityType: CommandSceneDelegate.activityType)
        userActivity.targetContentIdentifier = CommandSceneDelegate.activityType
        if let session = commandSession {
            let request = UISceneSessionActivationRequest(session: session, userActivity: userActivity)
            UIApplication.shared.activateSceneSession(for: request) { [logger] error in
                logger.error("Command window activation failed: \(error.localizedDescription, privacy: .public)")
            }
        } else if pendingCreation == nil {
            let id = UUID()
            pendingCreation = id
            logger.notice("Opening one transient command window.")
            let request = UISceneSessionActivationRequest(role: .windowApplication, userActivity: userActivity)
            UIApplication.shared.activateSceneSession(for: request) { [weak self] error in
                guard let self, pendingCreation == id else { return }
                pendingCreation = nil
                logger.error("Command window creation failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        while ContinuousClock.now < deadline {
            if isReady { return true }
            do { try await Task.sleep(for: .milliseconds(50)) } catch { return false }
        }
        // Timing out does not cancel UIKit's activation; keep its reservation.
        logger.error("Command window did not become ready within five seconds.")
        return false
    }

    private func scheduleDismissal() {
        guard activity.activeCount == 0 else { return }
        dismissal?.cancel()
        let revision = activity.revision
        let delay: Duration = activity.failureCount > 0 ? .seconds(3) : .seconds(1.5)
        dismissal = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard let self, activity.canDismiss(revision: revision), let session = commandSession else { return }
            closingSessionID = session.persistentIdentifier
            logger.notice("Dismissing the completed command window.")
            UIApplication.shared.requestSceneSessionDestruction(session, options: nil) { [weak self] error in
                self?.closingSessionID = nil
                self?.logger.error("Command window dismissal failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
#endif
