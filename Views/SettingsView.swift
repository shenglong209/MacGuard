// SettingsView.swift
// MacGuard - Anti-Theft Alarm for macOS
// Created: 2025-12-18

import SwiftUI
import ServiceManagement

/// Main settings view for MacGuard
struct SettingsView: View {
    @ObservedObject var alarmManager: AlarmStateManager

    var body: some View {
        Form {
            // Permissions Section
            Section("Permissions") {
                permissionRow(
                    title: "Accessibility",
                    granted: alarmManager.hasAccessibilityPermission,
                    action: { alarmManager.requestAccessibilityPermission() }
                )

                permissionRow(
                    title: "Bluetooth",
                    granted: alarmManager.bluetoothManager.isBluetoothEnabled,
                    action: { openBluetoothSettings() }
                )
            }

            // Trusted Device Section
            Section("Trusted Device") {
                if let device = alarmManager.bluetoothManager.trustedDevice {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(device.name)
                                .font(.headline)
                            if let rssi = device.lastRSSI {
                                Text("\(rssi) dBm")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        if device.isNearby {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                        Button("Remove") {
                            alarmManager.bluetoothManager.removeTrustedDevice()
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    Text("No trusted device configured")
                        .foregroundColor(.secondary)
                    Button("Scan for Devices...") {
                        DeviceScannerWindowController.shared.show(bluetoothManager: alarmManager.bluetoothManager)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            // Security Section
            Section("Security") {
                HStack {
                    Text("Backup PIN")
                    Spacer()
                    if alarmManager.authManager.hasPIN {
                        Text("Set")
                            .foregroundColor(.green)
                        Button("Change") {
                            PINSetupWindowController.shared.show(authManager: alarmManager.authManager)
                        }
                    } else {
                        Button("Set PIN") {
                            PINSetupWindowController.shared.show(authManager: alarmManager.authManager)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                HStack {
                    Text("Touch ID")
                    Spacer()
                    if alarmManager.authManager.hasBiometrics {
                        Text("Available")
                            .foregroundColor(.green)
                    } else {
                        Text("Not available")
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Startup Section
            Section("Startup") {
                LaunchAtLoginToggle()
            }

            // About Section
            Section("About") {
                LabeledContent("Version", value: "1.0.0")
                LabeledContent("macOS", value: "13.0+ (Ventura)")
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 500)
    }

    // MARK: - Helper Views

    @ViewBuilder
    private func permissionRow(title: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else {
                Button("Grant") {
                    action()
                }
                .buttonStyle(.borderedProminent)
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

#Preview {
    SettingsView(alarmManager: AlarmStateManager())
}
