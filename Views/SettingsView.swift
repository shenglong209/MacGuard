// SettingsView.swift
// MacGuard - Anti-Theft Alarm for macOS
// Created: 2025-12-18

import SwiftUI
import ServiceManagement

/// Main settings view for MacGuard
struct SettingsView: View {
    @ObservedObject var alarmManager: AlarmStateManager
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(spacing: 0) {
            // Modern header with animated top bar
            VStack(spacing: 0) {
                // Animated status bar at top
                Rectangle()
                    .fill(headerBarGradient)
                    .frame(height: 3)
                    .animation(.easeInOut(duration: 0.5), value: alarmManager.state)

                // Header content
                HStack(spacing: 14) {
                    // App icon with glow when armed
                    if let iconImage = loadAppIcon() {
                        Image(nsImage: iconImage)
                            .resizable()
                            .frame(width: 56, height: 56)
                            .cornerRadius(12)
                            .shadow(
                                color: alarmManager.state != .idle ? .green.opacity(0.4) : .black.opacity(0.2),
                                radius: alarmManager.state != .idle ? 12 : 4,
                                x: 0, y: 2
                            )
                            .animation(.easeInOut(duration: 0.5), value: alarmManager.state)
                    } else {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.blue)
                    }

                    // Title and subtitle
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text("MacGuard")
                                .font(.title2.bold())
                            Text("v\(appVersion)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.primary.opacity(0.06))
                                .cornerRadius(4)
                        }
                        Text("Anti-Theft Protection")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Status indicator
                    HStack(spacing: 6) {
                        Circle()
                            .fill(alarmManager.state == .idle ? Color.gray : Color.green)
                            .frame(width: 8, height: 8)
                            .shadow(
                                color: alarmManager.state != .idle ? .green.opacity(0.6) : .clear,
                                radius: 4
                            )
                        Text(alarmManager.state == .idle ? "Disarmed" : "Protected")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(alarmManager.state == .idle ? .secondary : .green)
                    }
                    .animation(.easeInOut(duration: 0.3), value: alarmManager.state)

                    // Quick action button
                    Button {
                        if alarmManager.state == .idle {
                            alarmManager.arm()
                        } else {
                            alarmManager.disarm()
                        }
                    } label: {
                        Image(systemName: alarmManager.state == .idle ? "shield" : "shield.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(alarmManager.state == .idle ? .secondary : .green)
                            .frame(width: 36, height: 36)
                            .background(Color.primary.opacity(0.06))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .help(alarmManager.state == .idle ? "Arm MacGuard" : "Disarm MacGuard")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            Form {
                // Permissions Section
                Section {
                    permissionRow(
                        icon: "hand.raised.fill",
                        title: "Accessibility",
                        subtitle: "Required for input monitoring",
                        granted: alarmManager.hasAccessibilityPermission,
                        action: { alarmManager.requestAccessibilityPermission() }
                    )

                    permissionRow(
                        icon: "antenna.radiowaves.left.and.right",
                        title: "Bluetooth",
                        subtitle: "For proximity detection",
                        granted: alarmManager.bluetoothManager.isBluetoothEnabled,
                        action: { openBluetoothSettings() }
                    )
                } header: {
                    Label("Permissions", systemImage: "checkmark.shield")
                }

                // Trusted Device Section
                Section {
                    if let device = alarmManager.bluetoothManager.trustedDevice {
                        HStack(spacing: 12) {
                            Image(systemName: deviceIcon(for: device.name))
                                .font(.title2)
                                .foregroundColor(.blue)
                                .frame(width: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.name)
                                    .font(.headline)
                                if let rssi = device.lastRSSI {
                                    Text("Signal: \(rssi) dBm")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            if device.isNearby {
                                Label("Nearby", systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                            Button("Remove") {
                                alarmManager.bluetoothManager.removeTrustedDevice()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("No trusted device configured")
                                .foregroundColor(.secondary)
                            Button {
                                DeviceScannerWindowController.shared.show(bluetoothManager: alarmManager.bluetoothManager)
                            } label: {
                                Label("Scan for Devices", systemImage: "wave.3.right")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                } header: {
                    Label("Trusted Device", systemImage: "iphone")
                }

                // Security Section
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "number.square.fill")
                            .font(.title2)
                            .foregroundColor(.orange)
                            .frame(width: 32)
                        Text("Backup PIN")
                        Spacer()
                        if alarmManager.authManager.hasPIN {
                            Label("Configured", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                            Button("Change") {
                                PINSetupWindowController.shared.show(authManager: alarmManager.authManager)
                            }
                            .controlSize(.small)
                        } else {
                            Button("Set PIN") {
                                PINSetupWindowController.shared.show(authManager: alarmManager.authManager)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }

                    HStack(spacing: 12) {
                        Image(systemName: "touchid")
                            .font(.title2)
                            .foregroundColor(.pink)
                            .frame(width: 32)
                        Text("Touch ID")
                        Spacer()
                        if alarmManager.authManager.hasBiometrics {
                            Label("Available", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                        } else {
                            Text("Not available")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Label("Security", systemImage: "lock.fill")
                }

                // Behavior Section
                Section {
                    Toggle("Lock screen when armed", isOn: $settings.autoLockOnArm)

                    Picker("Countdown duration", selection: $settings.countdownDuration) {
                        Text("Immediately").tag(0)
                        Text("3 seconds").tag(3)
                        Text("5 seconds").tag(5)
                        Text("10 seconds").tag(10)
                        Text("15 seconds").tag(15)
                        Text("30 seconds").tag(30)
                    }

                    // Lid Close Protection with warning
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("Lid close alarm (requires admin)", isOn: $settings.lidCloseProtection)

                        if settings.lidCloseProtection {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                    .font(.caption)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Mac won't sleep when lid closes while armed")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("Requires password prompt when arming")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.leading, 4)
                        }
                    }

                    Picker("Alarm Sound", selection: Binding(
                        get: { settings.alarmSound },
                        set: { newValue in
                            if newValue == .custom {
                                _ = settings.selectCustomSound()
                            } else {
                                settings.alarmSound = newValue
                            }
                        }
                    )) {
                        ForEach(AlarmSound.allCases.filter { $0.isAvailable }) { sound in
                            Text(sound.rawValue).tag(sound)
                        }
                    }

                    // Show custom file info when custom is selected
                    if settings.alarmSound == .custom {
                        HStack {
                            Image(systemName: "music.note")
                                .foregroundColor(.secondary)
                            Text(settings.customSoundName)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button("Change") {
                                _ = settings.selectCustomSound()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                    HStack {
                        Text("Volume")
                        Slider(value: $settings.alarmVolume, in: 0.5...1.0)
                        Button {
                            settings.previewSound()
                        } label: {
                            Image(systemName: "speaker.wave.2")
                        }
                        .buttonStyle(.borderless)
                    }
                } header: {
                    Label("Behavior", systemImage: "gearshape.2")
                }

                // Startup Section
                Section {
                    LaunchAtLoginToggle()
                } header: {
                    Label("Startup", systemImage: "power")
                }

                // About Section
                Section {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown")
                    LabeledContent("macOS", value: macOSVersion)

                    // Check for Updates button
                    HStack {
                        Text("Updates")
                        Spacer()
                        CheckForUpdatesButton()
                    }

                    Link(destination: URL(string: "https://github.com/shenglong209/MacGuard")!) {
                        HStack {
                            Text("GitHub Repository")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Label("About", systemImage: "info.circle")
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 420, height: 680)
    }

    // MARK: - Computed Properties

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var macOSVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    private var headerBarGradient: LinearGradient {
        if alarmManager.state != .idle {
            return LinearGradient(
                colors: [.green],
                startPoint: .leading,
                endPoint: .trailing
            )
        } else {
            return LinearGradient(
                colors: [
                    Color(red: 0.4, green: 0.49, blue: 0.92),
                    Color(red: 0.61, green: 0.3, blue: 0.79),
                    Color(red: 0.91, green: 0.3, blue: 0.55)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    // MARK: - Helper Functions

    private func loadAppIcon() -> NSImage? {
        guard let url = ResourceBundle.url(forResource: "AppIcon", withExtension: "png", subdirectory: "Resources"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        return image
    }

    private func deviceIcon(for name: String) -> String {
        let lowered = name.lowercased()
        if lowered.contains("iphone") { return "iphone" }
        if lowered.contains("watch") { return "applewatch" }
        if lowered.contains("ipad") { return "ipad" }
        if lowered.contains("airpods") { return "airpodspro" }
        return "wave.3.right"
    }

    @ViewBuilder
    private func permissionRow(icon: String, title: String, subtitle: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(granted ? .green : .blue)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
            } else {
                Button("Grant") {
                    action()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }

    // MARK: - Actions

    private func openBluetoothSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.Bluetooth") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - PIN Setup Window Controller

class PINSetupWindowController: NSObject, NSWindowDelegate {
    static let shared = PINSetupWindowController()

    private var window: NSWindow?
    private var hostingController: NSHostingController<PINSetupContainerView>?
    private var viewModel = PINSetupViewModel()

    private override init() {
        super.init()
    }

    func show(authManager: AuthManager) {
        viewModel.authManager = authManager
        viewModel.pin = ""
        viewModel.confirmPIN = ""
        viewModel.showError = false

        if window == nil {
            createWindow()
        }

        // Temporarily become a regular app to take focus
        NSApp.setActivationPolicy(.regular)

        // Force app activation and window focus
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)

        // Make first text field first responder after a brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.focusFirstTextField()
        }
    }

    private func createWindow() {
        let view = PINSetupContainerView(viewModel: viewModel, onDismiss: { [weak self] in
            self?.window?.orderOut(nil)
            // Revert to accessory app (menu bar only)
            NSApp.setActivationPolicy(.accessory)
        })
        hostingController = NSHostingController(rootView: view)

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        newWindow.contentViewController = hostingController
        newWindow.title = "Set Backup PIN"
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self

        window = newWindow
    }

    private func focusFirstTextField() {
        // Find and focus the first text field in the window
        guard let contentView = window?.contentView else { return }
        if let textField = findFirstTextField(in: contentView) {
            window?.makeFirstResponder(textField)
        }
    }

    private func findFirstTextField(in view: NSView) -> NSTextField? {
        for subview in view.subviews {
            if let textField = subview as? NSTextField, textField.isEditable {
                return textField
            }
            if let found = findFirstTextField(in: subview) {
                return found
            }
        }
        return nil
    }

    func windowWillClose(_ notification: Notification) {
        viewModel.pin = ""
        viewModel.confirmPIN = ""
        // Revert to accessory app when window closes via X button
        NSApp.setActivationPolicy(.accessory)
    }
}

class PINSetupViewModel: ObservableObject {
    var authManager: AuthManager?
    @Published var pin = ""
    @Published var confirmPIN = ""
    @Published var showError = false
    @Published var errorMessage = ""
}

struct PINSetupContainerView: View {
    @ObservedObject var viewModel: PINSetupViewModel
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Set Backup PIN")
                .font(.headline)

            // Use native AppKit text field for reliable input
            SecureTextFieldWrapper(text: $viewModel.pin, placeholder: "Enter PIN (4-8 digits)")
                .frame(width: 200, height: 24)

            SecureTextFieldWrapper(text: $viewModel.confirmPIN, placeholder: "Confirm PIN")
                .frame(width: 200, height: 24)

            if viewModel.showError {
                Text(viewModel.errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            HStack {
                Button("Cancel") {
                    onDismiss()
                }
                Button("Save") {
                    savePIN()
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.pin.count < 4)
            }
        }
        .padding(20)
        .frame(width: 280)
    }

    private func savePIN() {
        guard viewModel.pin.count >= 4, viewModel.pin.count <= 8 else {
            viewModel.errorMessage = "PIN must be 4-8 characters"
            viewModel.showError = true
            return
        }

        guard viewModel.pin == viewModel.confirmPIN else {
            viewModel.errorMessage = "PINs don't match"
            viewModel.showError = true
            viewModel.confirmPIN = ""
            return
        }

        if viewModel.authManager?.savePIN(viewModel.pin) == true {
            onDismiss()
        } else {
            viewModel.errorMessage = "Failed to save PIN"
            viewModel.showError = true
        }
    }
}

// MARK: - Native AppKit SecureTextField Wrapper

struct SecureTextFieldWrapper: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String

    func makeNSView(context: Context) -> NSSecureTextField {
        let textField = NSSecureTextField()
        textField.placeholderString = placeholder
        textField.delegate = context.coordinator
        textField.bezelStyle = .roundedBezel
        return textField
    }

    func updateNSView(_ nsView: NSSecureTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SecureTextFieldWrapper

        init(_ parent: SecureTextFieldWrapper) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                parent.text = textField.stringValue
            }
        }
    }
}

// MARK: - Launch at Login Toggle

struct LaunchAtLoginToggle: View {
    @State private var isEnabled = LaunchAtLoginManager.isEnabled

    var body: some View {
        Toggle("Launch at Login", isOn: $isEnabled)
            .onChange(of: isEnabled) { newValue in
                LaunchAtLoginManager.isEnabled = newValue
            }
    }
}

// MARK: - Launch at Login Manager

enum LaunchAtLoginManager {
    static var isEnabled: Bool {
        get {
            SMAppService.mainApp.status == .enabled
        }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("[LaunchAtLogin] Failed to update: \(error)")
            }
        }
    }
}

// MARK: - Check for Updates Button

struct CheckForUpdatesButton: View {
    @ObservedObject private var updateManager = UpdateManager.shared

    var body: some View {
        Button("Check for Updates...") {
            updateManager.checkForUpdates()
        }
        .disabled(!updateManager.canCheckForUpdates)
    }
}

#Preview {
    SettingsView(alarmManager: AlarmStateManager())
}
