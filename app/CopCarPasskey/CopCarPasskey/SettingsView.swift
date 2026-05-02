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
                    Text("Hold the ESP32 button for 5 seconds until it blinks rapidly, then tap Provision New Device.")
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
        case .idle:
            Button {
                provisioning.beginProvisioning()
            } label: {
                Label("Provision New Device", systemImage: "wifi.router")
            }

        case .waitingForWifi:
            VStack(alignment: .leading, spacing: 10) {
                Label("Connect to the device Wi-Fi", systemImage: "wifi")
                    .font(.headline)
                Text("1. Open **Settings → Wi-Fi** on this phone.\n2. Join **\(ProvisioningConstants.ssid)** (password: \(ProvisioningConstants.password)).\n3. Return here and tap Send Key.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Button("Send Key") {
                        guard let secret = SecretStore.load() else { return }
                        Task { await provisioning.sendKey(secret: secret) }
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Cancel", role: .cancel) { provisioning.reset() }
                }
                .padding(.top, 4)
            }
            .padding(.vertical, 4)

        case .sending:
            Label("Sending key…", systemImage: "arrow.up.circle")
                .foregroundStyle(.secondary)

        case .success:
            VStack(alignment: .leading, spacing: 6) {
                Label("Provisioned successfully", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("You can now reconnect to your normal Wi-Fi network.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Done") { provisioning.reset() }
                    .font(.caption)
            }

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
        }
    }
}
