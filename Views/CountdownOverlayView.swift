// CountdownOverlayView.swift
// MacGuard - Anti-Theft Alarm for macOS
// Created: 2025-12-18

import SwiftUI

/// Fullscreen countdown overlay shown during alarm trigger
struct CountdownOverlayView: View {
    @ObservedObject var alarmManager: AlarmStateManager

    @State private var showPINEntry = false

    var body: some View {
        ZStack {
            // Dark overlay background
            Color.black.opacity(0.85)
                .edgesIgnoringSafeArea(.all)

            VStack(spacing: 30) {
                // Warning icon
                Image(systemName: iconName)
                    .font(.system(size: 80))
                    .foregroundColor(iconColor)

                // Title
                Text(titleText)
                    .font(.largeTitle.bold())
                    .foregroundColor(.white)

                // Countdown (only in triggered state)
                if alarmManager.state == .triggered {
                    Text("\(alarmManager.countdownSeconds)")
                        .font(.system(size: 120, weight: .bold, design: .rounded))
                        .foregroundColor(.red)

                    Text("Authenticate to disarm")
                        .foregroundColor(.gray)
                }

                // Auth buttons or PIN entry (mutually exclusive)
                if showPINEntry {
                    PINOverlay(
                        isPresented: $showPINEntry,
                        alarmManager: alarmManager
                    )
                } else {
                    HStack(spacing: 20) {
                        if alarmManager.authManager.hasBiometrics {
                            Button(action: authenticateWithBiometrics) {
                                Label("Touch ID", systemImage: "touchid")
                                    .font(.title2)
                                    .padding()
                                    .frame(width: 160)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.blue)
                        }

                        if alarmManager.authManager.hasPIN {
                            Button(action: { showPINEntry = true }) {
                                Label("Enter PIN", systemImage: "number")
                                    .font(.title2)
                                    .padding()
                                    .frame(width: 160)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Computed Properties

    private var iconName: String {
        alarmManager.state == .alarming ? "bell.badge.fill" : "exclamationmark.triangle.fill"
    }

    private var iconColor: Color {
        alarmManager.state == .alarming ? .red : .yellow
    }

    private var titleText: String {
        alarmManager.state == .alarming ? "ALARM ACTIVE" : "UNAUTHORIZED ACCESS"
    }

    // MARK: - Actions

    private func authenticateWithBiometrics() {
        alarmManager.attemptBiometricDisarm { success in
            if !success {
                // Show PIN as fallback
                showPINEntry = true
            }
        }
    }
}

/// PIN entry overlay
struct PINOverlay: View {
    @Binding var isPresented: Bool
    @ObservedObject var alarmManager: AlarmStateManager

    @State private var pin = ""
    @State private var showError = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Enter PIN")
                .font(.headline)
                .foregroundColor(.white)

            // Use native AppKit text field for reliable input in overlay
            OverlaySecureTextField(text: $pin, placeholder: "PIN", onSubmit: validate)
                .frame(width: 200, height: 28)

            if showError {
                Text("Incorrect PIN")
                    .foregroundColor(.red)
            }

            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .buttonStyle(.bordered)

                Button("Verify") {
                    validate()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(30)
        .background(Color.gray.opacity(0.3))
        .cornerRadius(16)
    }

    private func validate() {
        if alarmManager.attemptPINDisarm(pin) {
            isPresented = false
        } else {
            showError = true
            pin = ""
        }
    }
}

// MARK: - Native SecureTextField for Overlay

struct OverlaySecureTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onSubmit: () -> Void

    func makeNSView(context: Context) -> NSSecureTextField {
        let textField = NSSecureTextField()
        textField.placeholderString = placeholder
        textField.delegate = context.coordinator
        textField.bezelStyle = .roundedBezel
        textField.font = NSFont.systemFont(ofSize: 14)
        textField.refusesFirstResponder = false

        // Focus the field once after a brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            textField.window?.makeFirstResponder(textField)
        }

        return textField
    }

    func updateNSView(_ nsView: NSSecureTextField, context: Context) {
        // Only update if different to avoid selection issues
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        // Do NOT call makeFirstResponder here - it causes text selection on every update
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: OverlaySecureTextField

        init(_ parent: OverlaySecureTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                parent.text = textField.stringValue
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            return false
        }
    }
}

#Preview {
    CountdownOverlayView(alarmManager: AlarmStateManager())
}
