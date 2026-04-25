import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var enrollment: EnrollmentManager
    @EnvironmentObject var provisioning: ProvisioningManager
    @StateObject private var watchSync  = WatchSyncManager.shared
    @State private var showConfirmRemove = false
    @State private var syncFeedback: String?

    var body: some View {
        List {
            Section("Key") {
                if enrollment.isEnrolled {
                    LabeledContent("Device", value: enrollment.enrolledLabel)
                    Button("Sync to Apple Watch") {
                        watchSync.pushSecretToWatch()
                        syncFeedback = watchSync.syncStatus
                    }
                    if let feedback = syncFeedback {
                        Text(feedback)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button("Remove Key", role: .destructive) {
                        showConfirmRemove = true
                    }
                } else {
                    Text("No key enrolled. Scan a QR code from the admin portal.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            }

            if enrollment.isEnrolled {
                Section {
                    provisionButton
                } header: {
                    Text("Device Setup")
                } footer: {
                    Text("Hold the ESP32 button for 5 seconds until it blinks rapidly, then tap Provision.")
                        .font(.caption)
                }
            }

            Section("About") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                LabeledContent("Watch Sync", value: watchSync.syncStatus)
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog("Remove Key", isPresented: $showConfirmRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { enrollment.removeKey() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This device will no longer be able to unlock. You can re-enroll from the admin portal.")
        }
    }

    @ViewBuilder
    private var provisionButton: some View {
        switch provisioning.state {
        case .success:
            Label("Provisioned successfully", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let msg):
            VStack(alignment: .leading, spacing: 4) {
                Label("Provisioning failed", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Try Again") { provisioning.reset() }
                    .font(.caption)
            }
        case .connectingToAP:
            Label("Connecting to device…", systemImage: "wifi")
                .foregroundStyle(.secondary)
        case .sending:
            Label("Sending key…", systemImage: "arrow.up.circle")
                .foregroundStyle(.secondary)
        case .idle:
            Button {
                guard let secret = SecretStore.load() else { return }
                Task { await provisioning.provision(secret: secret) }
            } label: {
                Label("Provision New Device", systemImage: "wifi.router")
            }
        }
    }
}
