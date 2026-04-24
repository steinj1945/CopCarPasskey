import SwiftUI

struct ContentView: View {
    @EnvironmentObject var peripheral: PasskeyPeripheral
    @EnvironmentObject var enrollment: EnrollmentManager

    var body: some View {
        NavigationStack {
            ZStack {
                background
                content
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

    // Drop your stock photo into Assets.xcassets as "AppBackground" to replace the dark placeholder
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

    private var content: some View {
        VStack(spacing: 32) {
            // Status ring
            ZStack {
                Circle()
                    .stroke(peripheral.isAdvertising ? Color.green.opacity(0.2) : Color.gray.opacity(0.1), lineWidth: 20)
                    .frame(width: 160, height: 160)
                Image(systemName: enrollment.isEnrolled ? "key.fill" : "key.slash")
                    .font(.system(size: 52))
                    .foregroundStyle(peripheral.isAdvertising ? .green : .gray)
            }

            VStack(spacing: 6) {
                Text(peripheral.isAdvertising ? "Broadcasting" : "Inactive")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
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
                VStack(spacing: 8) {
                    Text("No key enrolled")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Scan the QR code from the admin portal to enroll your device.")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)
            }
        }
        .padding()
    }
}
