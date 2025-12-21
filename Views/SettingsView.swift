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
            headerView

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
                        trustedDeviceRow(device)

                        Picker("Detection Distance", selection: $settings.proximityDistance) {
                            ForEach(ProximityDistance.allCases) { distance in
                                Text("\(distance.rawValue) (\(distance.description))").tag(distance)
                            }
                        }
                        .pickerStyle(.menu)

                        Toggle("Auto-arm when device leaves", isOn: $settings.autoArmOnDeviceLeave)

                        if settings.autoArmOnDeviceLeave {
                            Picker("Grace period", selection: $settings.autoArmGracePeriod) {
                                Text("10 seconds").tag(10)
                                Text("15 seconds").tag(15)
                                Text("30 seconds").tag(30)
                                Text("60 seconds").tag(60)
                            }
                            .pickerStyle(.menu)
                        }
                    } else {
                        noDeviceConfigured
                    }
                } header: {
                    Label("Trusted Device", systemImage: "iphone")
                }

                // Security Section
                Section {
                    securityPINRow
                    securityTouchIDRow
                } header: {
                    Label("Security", systemImage: "lock.fill")
                }

                // Behavior Section
                Section {
                    behaviorSection
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
                    aboutSection
                } header: {
                    Label("About", systemImage: "info.circle")
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 420, height: 680)
    }

    // MARK: - Header View

    private var headerView: some View {
        VStack(spacing: 0) {
            // Animated status bar at top
            Rectangle()
                .fill(headerBarGradient)
                .frame(height: 3)
                .animation(.easeInOut(duration: 0.5), value: alarmManager.state)

            // Header content
            HStack(spacing: Theme.Spacing.lg) {
                // App icon with glow when armed
                if let iconImage = loadAppIcon() {
                    Image(nsImage: iconImage)
                        .resizable()
                        .frame(width: 56, height: 56)
                        .cornerRadius(Theme.CornerRadius.lg)
                        .shadow(
                            color: alarmManager.state != .idle ? Theme.StateColor.armed.opacity(0.4) : .black.opacity(0.2),
                            radius: alarmManager.state != .idle ? 12 : 4,
                            x: 0, y: 2
                        )
                        .animation(.easeInOut(duration: 0.5), value: alarmManager.state)
                } else {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 40))
                        .foregroundColor(Theme.Accent.primary)
                }

                // Title and subtitle
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Text("MacGuard")
                            .font(.title2.bold())

                        // Version badge with glass pill
                        Text("v\(appVersion)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, Theme.Spacing.sm)
                            .padding(.vertical, 2)
                            .background {
                                Capsule()
                                    .fill(.clear)
                                    .background(
                                        VisualEffectView(
                                            material: .hudWindow,
                                            blendingMode: .withinWindow
                                        )
                                    )
                                    .clipShape(Capsule())
                            }
                            .glassCapsuleBorder()
                    }
                    Text("Anti-Theft Protection")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Status indicator
                HStack(spacing: Theme.Spacing.sm) {
                    Circle()
                        .fill(alarmManager.state == .idle ? Theme.StateColor.idle : Theme.StateColor.armed)
                        .frame(width: 8, height: 8)
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    (alarmManager.state != .idle ? Theme.StateColor.armed : Theme.StateColor.idle).opacity(0.3),
                                    lineWidth: 1
                                )
                        )
                        .shadow(
                            color: alarmManager.state != .idle ? Theme.StateColor.armed.opacity(0.6) : .clear,
                            radius: 4
                        )
                    Text(alarmManager.state == .idle ? "Disarmed" : "Protected")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(alarmManager.state == .idle ? .secondary : Theme.StateColor.armed)
                }
                .animation(.easeInOut(duration: 0.3), value: alarmManager.state)

                // Quick action button with glass
                Button {
                    if alarmManager.state == .idle {
                        alarmManager.arm()
                    } else {
                        alarmManager.disarm()
                    }
                } label: {
                    Image(systemName: alarmManager.state == .idle ? "shield" : "shield.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(alarmManager.state == .idle ? .secondary : Theme.StateColor.armed)
                }
                .buttonStyle(GlassIconButtonStyle(size: 36))
                .help(alarmManager.state == .idle ? "Arm MacGuard" : "Disarm MacGuard")
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.vertical, Theme.Spacing.lg)
        }
        .background {
            GlassBackground(material: .headerView, cornerRadius: 0, showBorder: false)
        }
    }

    // MARK: - Trusted Device Row

    private func trustedDeviceRow(_ device: TrustedDevice) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            ZStack {
                GlassIconCircle(size: 32, material: .selection)
                Image(systemName: device.icon)
                    .font(.title2)
                    .foregroundColor(Theme.Accent.primary)
            }

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
            if alarmManager.bluetoothManager.isDeviceNearby {
                Label("Nearby", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(Theme.StateColor.armed)
            }
            Button("Remove") {
                alarmManager.bluetoothManager.removeTrustedDevice()
            }
            .buttonStyle(GlassSecondaryButtonStyle())
        }
    }

    // MARK: - No Device Configured

    private var noDeviceConfigured: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("No trusted device configured")
                .foregroundColor(.secondary)
            Button {
                DeviceScannerWindowController.shared.show(bluetoothManager: alarmManager.bluetoothManager)
            } label: {
                Label("Scan for Devices", systemImage: "wave.3.right")
            }
            .buttonStyle(GlassBorderedProminentButtonStyle(tint: Theme.Accent.primary))
        }
    }

    // MARK: - Security Rows

    private var securityPINRow: some View {
        HStack(spacing: Theme.Spacing.md) {
            ZStack {
                GlassIconCircle(size: 32, material: .selection)
                Image(systemName: "number.square.fill")
                    .font(.title2)
                    .foregroundColor(Theme.StateColor.triggered)
            }
            Text("Backup PIN")
            Spacer()
            if alarmManager.authManager.hasPIN {
                Label("Configured", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(Theme.StateColor.armed)
                Button("Change") {
                    PINSetupWindowController.shared.show(authManager: alarmManager.authManager)
                }
                .buttonStyle(GlassSecondaryButtonStyle())
            } else {
                Button("Set PIN") {
                    PINSetupWindowController.shared.show(authManager: alarmManager.authManager)
                }
                .buttonStyle(GlassBorderedProminentButtonStyle(tint: Theme.Accent.primary))
            }
        }
    }

    private var securityTouchIDRow: some View {
        HStack(spacing: Theme.Spacing.md) {
            ZStack {
                GlassIconCircle(size: 32, material: .selection)
                Image(systemName: "touchid")
                    .font(.title2)
                    .foregroundColor(.pink)
            }
            Text("Touch ID")
            Spacer()
            if alarmManager.authManager.hasBiometrics {
                Label("Available", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(Theme.StateColor.armed)
            } else {
                Text("Not available")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Behavior Section

    @ViewBuilder
    private var behaviorSection: some View {
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
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Toggle("Lid close alarm (requires admin)", isOn: $settings.lidCloseProtection)

            if settings.lidCloseProtection {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(Theme.StateColor.triggered)
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
                .padding(.leading, Theme.Spacing.xs)
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
                .buttonStyle(GlassSecondaryButtonStyle())
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
    }

    // MARK: - About Section

    @ViewBuilder
    private var aboutSection: some View {
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
                colors: [Theme.StateColor.armed],
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

    @ViewBuilder
    private func permissionRow(icon: String, title: String, subtitle: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            ZStack {
                GlassIconCircle(size: 32, material: .selection)
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(granted ? Theme.StateColor.armed : Theme.Accent.primary)
            }
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
                    .foregroundColor(Theme.StateColor.armed)
            } else {
                Button("Grant") {
                    action()
                }
                .buttonStyle(GlassBorderedProminentButtonStyle(tint: Theme.Accent.primary))
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
        VStack(spacing: Theme.Spacing.lg) {
            Text("Set Backup PIN")
                .font(.headline)

            // Use native AppKit text field for reliable input
            SecureTextFieldWrapper(text: $viewModel.pin, placeholder: "Enter PIN (4-8 digits)")
                .frame(width: 200, height: 24)

            SecureTextFieldWrapper(text: $viewModel.confirmPIN, placeholder: "Confirm PIN")
                .frame(width: 200, height: 24)

            if viewModel.showError {
                Text(viewModel.errorMessage)
                    .foregroundColor(Theme.StateColor.alarming)
                    .font(.caption)
            }

            HStack {
                Button("Cancel") {
                    onDismiss()
                }
                .buttonStyle(GlassSecondaryButtonStyle())

                Button("Save") {
                    savePIN()
                }
                .buttonStyle(GlassBorderedProminentButtonStyle(tint: Theme.Accent.primary))
                .disabled(viewModel.pin.count < 4)
            }
        }
        .padding(Theme.Spacing.xl)
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
