import SwiftUI
import VisionKit

struct ContentView: View {
    @EnvironmentObject var peripheral: PasskeyPeripheral
    @EnvironmentObject var enrollment: EnrollmentManager
    @State private var showScanner = false
    @State private var authPulse = false

    var body: some View {
        NavigationStack {
            ZStack {
                background
                content
            }
            .sheet(isPresented: $showScanner) {
                if DataScannerViewController.isAvailable {
                    QRScannerView { payload in
                        showScanner = false
                        guard let url = URL(string: payload) else {
                            enrollment.enrollmentError = "QR code did not contain a valid URL"
                            return
                        }
                        do {
                            try enrollment.enroll(from: url)
                            WatchSyncManager.shared.pushSecretToWatch()
                        } catch {
                            enrollment.enrollmentError = error.localizedDescription
                        }
                    }
                } else {
                    ContentUnavailableView("Scanner Unavailable",
                        systemImage: "qrcode.viewfinder",
                        description: Text("This device does not support the QR scanner."))
                }
            }
            .alert("Enrollment Failed", isPresented: Binding(
                get: { enrollment.enrollmentError != nil },
                set: { if !$0 { enrollment.enrollmentError = nil } }
            )) {
                Button("OK", role: .cancel) { enrollment.enrollmentError = nil }
            } message: {
                Text(enrollment.enrollmentError ?? "")
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("CopCar Passkey")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gear")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 1)
                    }
                }
            }
        }
    }

    private var background: some View {
        ZStack {
            Image("AppBackground")
                .resizable()
                .scaledToFill()
            Color.black.opacity(0.40)
            LinearGradient(
                colors: [.clear, .black.opacity(0.3)],
                startPoint: .center,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

    private var ringColor: Color {
        if peripheral.isAuthenticating { return .yellow }
        if peripheral.isAdvertising    { return .green }
        return .gray
    }

    private var ringOpacity: Double {
        if peripheral.isAuthenticating { return authPulse ? 0.6 : 0.15 }
        if peripheral.isAdvertising    { return 0.35 }
        return 0.12
    }

    private var statusText: String {
        if peripheral.isAuthenticating { return "Authenticating…" }
        if peripheral.isAdvertising    { return "Broadcasting" }
        return "Inactive"
    }

    private var content: some View {
        VStack(spacing: 32) {
            // Status ring
            ZStack {
                Circle()
                    .stroke(ringColor.opacity(ringOpacity), lineWidth: 20)
                    .frame(width: 160, height: 160)

                Image(systemName: enrollment.isEnrolled ? "key.fill" : "key.slash")
                    .font(.system(size: 52))
                    .foregroundStyle(ringColor)
                    .symbolEffect(.pulse, isActive: peripheral.isAuthenticating)
            }
            .onChange(of: peripheral.isAuthenticating) { _, authenticating in
                if authenticating {
                    withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                        authPulse = true
                    }
                } else {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        authPulse = false
                    }
                }
            }

            VStack(spacing: 6) {
                Text(statusText)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .animation(.default, value: statusText)
                if enrollment.isEnrolled {
                    Text(enrollment.enrolledLabel)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                }
                Text(peripheral.lastEvent)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
            }

            if !enrollment.isEnrolled {
                VStack(spacing: 16) {
                    VStack(spacing: 8) {
                        Text("No key enrolled")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("Scan the QR code from the admin portal to enroll your device.")
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.75))
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        showScanner = true
                    } label: {
                        Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                            .font(.headline)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(.white.opacity(0.15))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 32)
            }
        }
        .padding()
    }
}
