import SwiftUI

@main
struct CopCarPasskeyApp: App {
    @StateObject private var peripheral    = PasskeyPeripheral()
    @StateObject private var enrollment    = EnrollmentManager()
    @StateObject private var watchSync     = WatchSyncManager.shared
    @StateObject private var provisioning  = ProvisioningManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(peripheral)
                .environmentObject(enrollment)
                .environmentObject(watchSync)
                .environmentObject(provisioning)
                .onOpenURL { url in
                    guard url.scheme == DeepLink.scheme else { return }
                    try? enrollment.enroll(from: url)
                    // Auto-push to Watch after successful enrollment
                    watchSync.pushSecretToWatch()
                }
        }
    }
}
