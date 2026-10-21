// SettingsView.swift
// MacGuard - Anti-Theft Alarm for macOS
// Created: 2025-12-18

import SwiftUI
import ServiceManagement

/// Main settings view for MacGuard
struct SettingsView: View {
    @ObservedObject var alarmManager: AlarmStateManager
    @ObservedObject private var settings = AppSettings.shared

    /// Read-only unless idle: a trusted device suppresses triggers, so anyone near it could edit.
    private var isLocked: Bool { alarmManager.state != .idle }

    var body: some View {
        VStack(spacing: 0) {
            // Modern header with animated top bar
            headerView

            Divider()

            Form {
                if isLocked {
                    Label("Disarm to change settings", systemImage: "lock.fill")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }

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

                // Trusted Devices Section
                Section {
                    if alarmManager.bluetoothManager.trustedDevices.isEmpty {
                        noDeviceConfigured
                    } else {
                        // Simple device list (read-only summary)
                        ForEach(alarmManager.bluetoothManager.trustedDevices) { device in
                            simpleTrustedDeviceRow(device)
                        }
                    }

                    // Configure button (right-aligned)
                    HStack {
                        Spacer()
                        Button {
                            TrustedDevicesConfigWindowController.shared.show(bluetoothManager: alarmManager.bluetoothManager)
                        } label: {
                            Label(
                                alarmManager.bluetoothManager.trustedDevices.isEmpty ? "Add Devices" : "Manage Devices",
                                systemImage: alarmManager.bluetoothManager.trustedDevices.isEmpty ? "plus.circle" : "gearshape"
                            )
                        }
                        .buttonStyle(GlassBorderedProminentButtonStyle(tint: Theme.Accent.primary))
                    }
                } header: {
                    HStack {
                        Label("Trusted Devices", systemImage: "iphone")
                        if !alarmManager.bluetoothManager.trustedDevices.isEmpty {
                            Text("(\(alarmManager.bluetoothManager.trustedDevices.count))")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .disabled(isLocked)

                // Security Section
                Section {
                    securityPINRow
                    securityTouchIDRow
                } header: {
                    Label("Security", systemImage: "lock.fill")
                }
                .disabled(isLocked)

                // Behavior Section
                Section {
                    behaviorSection
                    TriggerSettingsView()
                } header: {
                    Label("Behavior", systemImage: "gearshape.2")
                }
                .disabled(isLocked)


                // Startup Section
                Section {
                    LaunchAtLoginToggle()
                    TamperSettingsView()
                } header: {
                    Label("Startup", systemImage: "power")
                }
                .disabled(isLocked)

                // Event Log Section
                Section {
                    activityLogSection
                } header: {
                    Label("Event Log", systemImage: "list.bullet.rectangle")
                }

                // About Section
                Section {
                    aboutSection
                } header: {
                    Label("About", systemImage: "info.circle")
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .frame(width: 420, height: 680)
        .background {
            VisualEffectView(
                material: .sidebar,
                blendingMode: .behindWindow,
                isEmphasized: true
            )
            .ignoresSafeArea()
        }
    }

    // MARK: - Header View

    private var headerView: some View {
        VStack(spacing: 0) {
            // Animated status bar at top
            Rectangle()
                .fill(headerBarGradient)
                .frame(height: 3)
                .animation(.easeInOut(duration: 0.5), value: alarmManager.state.phase)

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
                        .animation(.easeInOut(duration: 0.5), value: alarmManager.state.phase)
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
                .animation(.easeInOut(duration: 0.3), value: alarmManager.state.phase)

                // Quick action button with glass
                Button {
                    switch alarmManager.state {
                    case .idle: alarmManager.arm()
                    case .arming: alarmManager.cancelArming()
                    case .armed, .triggered, .alarming: alarmManager.requestDisarm()
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

    // MARK: - Simple Trusted Device Row (for Settings summary)

    private func simpleTrustedDeviceRow(_ device: TrustedDevice) -> some View {
        let connectionStatus = alarmManager.bluetoothManager.connectionStatus(for: device)
        let isNearby = alarmManager.bluetoothManager.isNearby(device)

        return HStack(spacing: Theme.Spacing.md) {
            Image(systemName: device.icon)
                .font(.title3)
                .foregroundColor(Theme.Accent.primary)
                .frame(width: 24)

            Text(device.name)
                .font(.body)

            Spacer()

            // Status indicator
            HStack(spacing: Theme.Spacing.xs) {
                if isNearby {
                    Circle()
                        .fill(Theme.StateColor.armed)
                        .frame(width: 8, height: 8)
                    Text("Nearby")
                        .font(.caption)
                        .foregroundColor(Theme.StateColor.armed)
                } else {
                    Circle()
                        .fill(Color.secondary.opacity(0.5))
                        .frame(width: 8, height: 8)
                    Text(connectionStatus.label)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - No Device Configured

    private var noDeviceConfigured: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("No trusted devices configured")
                .foregroundColor(.secondary)
            Text("Add a device to enable proximity features")
                .font(.caption)
                .foregroundStyle(.tertiary)
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
                Label("Set", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(Theme.StateColor.armed)
                Button("Change PIN") {
                    PINSetupWindowController.shared.show(alarmManager: alarmManager)
                }
                .buttonStyle(GlassSecondaryButtonStyle())
            } else {
                Button("Set PIN") {
                    PINSetupWindowController.shared.show(alarmManager: alarmManager)
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
            ForEach(CountdownDuration.allCases) { duration in
                Text(duration.label).tag(duration)
            }
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
                    settings.chooseSound(newValue)
                }
            }
        )) {
            ForEach(AlarmSound.offered) { sound in
                Text(sound.rawValue).tag(sound)
            }
        }

        if settings.customSoundUnavailable {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("'\(settings.customSoundName)' can't be played - using the default sound")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                Spacer()
                Button("Choose…") {
                    _ = settings.selectCustomSound()
                }
                .buttonStyle(GlassSecondaryButtonStyle())
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
            Slider(value: $settings.alarmVolume, in: AlarmVolume.range)
            Button {
                settings.previewSound()
            } label: {
                Image(systemName: "speaker.wave.2")
            }
            .buttonStyle(.borderless)
        }
    }

    // MARK: - Event Log Section

    @ViewBuilder
    private var activityLogSection: some View {
        HStack(spacing: Theme.Spacing.md) {
            ZStack {
                GlassIconCircle(size: 32, material: .selection)
                Image(systemName: "doc.text")
                    .font(.title2)
                    .foregroundColor(Theme.Accent.info)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Recent Activity")
                Text("\(ActivityLogManager.shared.entries.count) entries")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("View Log") {
                ActivityLogWindowController.shared.show(alarmManager: alarmManager)
            }
            .buttonStyle(GlassBorderedProminentButtonStyle(tint: Theme.Accent.primary))
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

// MARK: - PIN Setup Window

@MainActor
final class PINSetupWindowController {
    static let shared = PINSetupWindowController()

    private let viewModel = PINSetupViewModel()
    private var window: UtilityWindow?

    func show(alarmManager: AlarmStateManager) {
        guard alarmManager.state == .idle else { return }
        viewModel.reset()
        window = window ?? UtilityWindow(
            title: "Set Backup PIN", size: NSSize(width: 300, height: 220), fitsContent: true,
            onClose: { [viewModel] in viewModel.reset() },
            content: PINSetupContainerView(viewModel: viewModel, alarmManager: alarmManager,
                                           onDismiss: { PINSetupWindowController.shared.close() }))
        window?.show()
    }

    func close() {
        window?.close()
    }
}

/// What the PIN window says under the fields.
enum PINFeedback: Equatable {
    case none
    case error(String)
    /// Saving `accepted` again keeps it despite the weakness.
    case weak(PINWeakness, accepted: String)
}

final class PINSetupViewModel: ObservableObject {
    @Published var pin = ""
    @Published var confirmPIN = ""
    @Published var feedback = PINFeedback.none

    func reset() {
        pin = ""
        confirmPIN = ""
        feedback = .none
    }
}

struct PINSetupContainerView: View {
    @ObservedObject var viewModel: PINSetupViewModel
    @ObservedObject var alarmManager: AlarmStateManager
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Text(alarmManager.authManager.hasPIN ? "Change Backup PIN" : "Set Backup PIN")
                .font(.headline)

            NativeSecureField(text: $viewModel.pin, placeholder: "Enter PIN (4-8 digits)", focusOnAppear: true)
                .frame(width: 200, height: 24)

            NativeSecureField(text: $viewModel.confirmPIN, placeholder: "Confirm PIN")
                .frame(width: 200, height: 24)

            switch viewModel.feedback {
            case .none:
                EmptyView()
            case .error(let message):
                feedbackLine(message)
            case .weak(let weakness, _):
                if weakness == .luggage, let gif = AnimatedGIF.luggage {
                    gif.frame(width: 240, height: 127)
                } else {
                    Text(weakness.message)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                feedbackLine("Save again to use it anyway.")
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

    private func feedbackLine(_ message: String) -> some View {
        Text(message)
            .foregroundColor(Theme.StateColor.alarming)
            .font(.caption)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func savePIN() {
        let accepted: String? = if case .weak(_, let accepted) = viewModel.feedback { accepted } else { nil }
        guard let pin = PIN(viewModel.pin) else {
            viewModel.feedback = .error("PIN must be 4-8 digits")
            return
        }
        guard viewModel.pin == viewModel.confirmPIN else {
            viewModel.feedback = .error("PINs don't match")
            viewModel.confirmPIN = ""
            return
        }
        if let weakness = pin.weakness, accepted != viewModel.pin {
            viewModel.feedback = .weak(weakness, accepted: viewModel.pin)
            return
        }
        // Re-checked at save time: the window may have been open when arming.
        guard alarmManager.state == .idle else {
            viewModel.feedback = .error("Disarm to change the PIN")
            return
        }
        if alarmManager.authManager.savePIN(pin) {
            onDismiss()
        } else {
            viewModel.feedback = .error("Failed to save PIN")
        }
    }
}

/// An animated GIF. `luggage` is a user-supplied file, never bundled.
struct AnimatedGIF: NSViewRepresentable {
    let url: URL

    static var luggage: AnimatedGIF? {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacGuard/luggage.gif")
        return FileManager.default.fileExists(atPath: url.path) ? AnimatedGIF(url: url) : nil
    }

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.image = NSImage(contentsOf: url)
        view.animates = true
        view.imageScaling = .scaleProportionallyUpOrDown
        return view
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {}
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
                logActivity(.system, "Failed to update launch at login: \(error)")
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
