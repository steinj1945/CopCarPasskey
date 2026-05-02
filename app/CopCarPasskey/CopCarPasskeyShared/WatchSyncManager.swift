import Foundation
import WatchConnectivity

/// Syncs the shared secret from iPhone → Watch over WatchConnectivity.
/// Runs on both targets; the iPhone sends, the Watch receives.
@MainActor
final class WatchSyncManager: NSObject, ObservableObject {
    static let shared = WatchSyncManager()

    @Published private(set) var syncStatus: String = "Not paired"

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // Called from iOS only — push secret to Watch
    func pushSecretToWatch() {
        guard WCSession.default.isPaired,
              WCSession.default.isWatchAppInstalled,
              let entry = SecretStore.loadEntry()
        else { return }

        let payload: [String: Any] = [
            "secret": entry.secret.base64EncodedString(),
            "label":  entry.label
        ]
        WCSession.default.transferUserInfo(payload)
        syncStatus = "Synced to Watch"
    }
}

extension WatchSyncManager: WCSessionDelegate {
    // Watch receives this
    nonisolated func session(_ session: WCSession,
                             didReceiveUserInfo userInfo: [String: Any]) {
        guard
            let b64     = userInfo["secret"] as? String,
            let secret  = Data(base64Encoded: b64),
            let label   = userInfo["label"] as? String
        else { return }

        Task { @MainActor in
            try? SecretStore.save(secret, label: label)
            syncStatus = "Key received from iPhone"
        }
    }

    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith state: WCSessionActivationState,
                             error: Error?) {
        Task { @MainActor in
            syncStatus = state == .activated ? "Session active" : "Session inactive"
        }
    }

    // iOS only — watchOS 26 SDK marks these unavailable on watchOS
    #if !os(watchOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
    #endif
}
