import SwiftUI

struct ContentView: View {
    @StateObject private var sim = ArduinoSimulator()
    @State private var secretHex: String = UserDefaults.standard.string(forKey: "secretHex") ?? ""

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HSplitView {
                controlPanel
                    .frame(minWidth: 260, maxWidth: 320)
                logPanel
                    .frame(minWidth: 320)
            }
        }
        .frame(minWidth: 640, minHeight: 420)
        .onAppear {
            applySecret(secretHex)
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .foregroundStyle(.secondary)
            Text("CopCar BLE Simulator")
                .font(.headline)
            Spacer()
            statusBadge
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var statusBadge: some View {
        let (label, color) = statusPresentation
        return Label(label, systemImage: "circle.fill")
            .foregroundStyle(color)
            .font(.caption.bold())
            .animation(.default, value: label)
    }

    // MARK: - Control panel

    private var controlPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            secretField
            statusDisplay
            Spacer()
            actionButtons
        }
        .padding()
    }

    private var secretField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Shared Secret (hex)", systemImage: "key")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            TextField("Paste hex from enrollment URL…", text: $secretHex)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
                .onChange(of: secretHex) { _, hex in
                    applySecret(hex)
                    UserDefaults.standard.set(hex, forKey: "secretHex")
                }
            if !secretHex.isEmpty && sim.sharedSecret.isEmpty {
                Text("Invalid hex")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
    }

    private var statusDisplay: some View {
        let (_, color) = statusPresentation
        return ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(.quinary)
            VStack(spacing: 10) {
                Image(systemName: statusIcon)
                    .font(.system(size: 44))
                    .foregroundStyle(color)
                    .symbolEffect(.pulse, isActive: sim.status == .scanning || sim.status == .authenticating)
                Text(statusLabel)
                    .font(.title3.bold())
                    .foregroundStyle(color)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
        .animation(.default, value: statusLabel)
    }

    private var actionButtons: some View {
        HStack {
            Button(action: { sim.reset() }) {
                Label("Reset", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.bordered)
            Spacer()
            Button(action: { sim.triggerAuth() }) {
                Label("Scan & Unlock", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!sim.status.isIdle)
        }
    }

    // MARK: - Log panel

    private var logPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Event Log")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear") { sim.eventLog.removeAll() }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(sim.eventLog) { entry in
                        HStack(alignment: .top, spacing: 8) {
                            Text(entry.time)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .frame(width: 54, alignment: .trailing)
                            Text(entry.message)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 2)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Helpers

    private func applySecret(_ hex: String) {
        let trimmed = hex.trimmingCharacters(in: .whitespaces)
        sim.sharedSecret = Data(hexString: trimmed) ?? Data()
    }

    private var statusPresentation: (String, Color) {
        switch sim.status {
        case .idle:                  return ("Idle", .secondary)
        case .bluetoothUnavailable:  return ("BT Unavailable", .red)
        case .scanning:              return ("Scanning…", .blue)
        case .connecting(let n):     return ("Connecting to \(n)…", .orange)
        case .authenticating:        return ("Authenticating…", .yellow)
        case .unlocked:              return ("Unlocked", .green)
        case .authFailed(let r):     return ("Failed: \(r)", .red)
        }
    }

    private var statusIcon: String {
        switch sim.status {
        case .idle:                  return "lock"
        case .bluetoothUnavailable:  return "bluetooth"
        case .scanning:              return "antenna.radiowaves.left.and.right"
        case .connecting:            return "cable.connector"
        case .authenticating:        return "key"
        case .unlocked:              return "lock.open.fill"
        case .authFailed:            return "xmark.shield"
        }
    }

    private var statusLabel: String {
        switch sim.status {
        case .idle:                  return "Ready"
        case .bluetoothUnavailable:  return "Bluetooth\nUnavailable"
        case .scanning:              return "Scanning…"
        case .connecting(let n):     return "Connecting\nto \(n)"
        case .authenticating:        return "Authenticating…"
        case .unlocked:              return "Unlocked!"
        case .authFailed(let r):     return "Failed\n\(r)"
        }
    }
}

private extension Data {
    init?(hexString: String) {
        let hex = hexString.trimmingCharacters(in: .whitespaces)
        guard !hex.isEmpty, hex.count % 2 == 0 else { return nil }
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        self = data
    }
}

#Preview {
    ContentView()
}
