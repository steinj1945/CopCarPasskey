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
            .navigationTitle("CopCar Passkey")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gear")
                    }
                }
            }
        }
    }

    // Drop your stock photo into Assets.xcassets as "AppBackground" to replace the dark placeholder
    private var background: some View {
        ZStack {
            Color(white: 0.08)  // placeholder until photo is added
            Image("AppBackground")
                .resizable()
                .scaledToFill()
        }
        .overlay(.ultraThinMaterial)
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
                if enrollment.isEnrolled {
                    Text(enrollment.enrolledLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(peripheral.lastEvent)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if !enrollment.isEnrolled {
                VStack(spacing: 8) {
                    Text("No key enrolled")
                        .font(.headline)
                    Text("Scan the QR code from the admin portal to enroll your device.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)
            }
        }
        .padding()
    }
}
