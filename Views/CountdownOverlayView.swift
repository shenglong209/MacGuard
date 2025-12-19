// CountdownOverlayView.swift
// MacGuard - Anti-Theft Alarm for macOS
// Created: 2025-12-18

import SwiftUI

/// Fullscreen countdown overlay shown during alarm trigger
struct CountdownOverlayView: View {
    @ObservedObject var alarmManager: AlarmStateManager

    @State private var showPINEntry = false
    @State private var iconScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.3

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Dark overlay background with gradient - fixed position
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.95),
                        alarmManager.state == .alarming ? Color.red.opacity(0.3) : Color.black.opacity(0.85)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                // Pulsing background circle for alarm state - centered and fixed
                if alarmManager.state == .alarming {
                    Circle()
                        .fill(Color.red.opacity(pulseOpacity))
                        .frame(width: 300, height: 300)
                        .blur(radius: 60)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                }

                VStack(spacing: 30) {
                // Warning icon with animation
                ZStack {
                    // Glow effect
                    Image(systemName: iconName)
                        .font(.system(size: 90))
                        .foregroundStyle(iconColor.opacity(0.5))
                        .blur(radius: 20)

                    Image(systemName: iconName)
                        .font(.system(size: 80))
                        .foregroundStyle(iconColor)
                        .symbolRenderingMode(.hierarchical)
                }
                .scaleEffect(iconScale)

                // Title
                Text(titleText)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .tracking(alarmManager.state == .alarming ? 4 : 1)

                // Countdown (only in triggered state)
                if alarmManager.state == .triggered {
                    ZStack {
                        // Background ring
                        Circle()
                            .stroke(Color.red.opacity(0.3), lineWidth: 8)
                            .frame(width: 160, height: 160)

                        // Progress ring
                        Circle()
                            .trim(from: 0, to: CGFloat(alarmManager.countdownSeconds) / CGFloat(AppSettings.shared.countdownDuration))
                            .stroke(Color.red, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .frame(width: 160, height: 160)
                            .rotationEffect(.degrees(-90))

                        Text("\(alarmManager.countdownSeconds)")
                            .font(.system(size: 72, weight: .bold, design: .rounded))
                            .foregroundStyle(.red)
                    }

                    Text("Authenticate to disarm")
                        .font(.body)
                        .foregroundStyle(.gray)
                }

                // Auth buttons or PIN entry (mutually exclusive)
                if showPINEntry {
                    PINOverlay(
                        isPresented: $showPINEntry,
                        alarmManager: alarmManager
                    )
                    .transition(.scale.combined(with: .opacity))
                } else {
                    HStack(spacing: 20) {
                        if alarmManager.authManager.hasBiometrics {
                            Button(action: authenticateWithBiometrics) {
                                HStack(spacing: 12) {
                                    Image(systemName: "touchid")
                                        .font(.title)
                                    Text("Touch ID")
                                        .font(.title3.weight(.semibold))
                                }
                                .padding(.horizontal, 24)
                                .padding(.vertical, 16)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.blue)
                        }

                        if alarmManager.authManager.hasPIN {
                            Button(action: { withAnimation { showPINEntry = true } }) {
                                HStack(spacing: 12) {
                                    Image(systemName: "number.square")
                                        .font(.title)
                                    Text("Enter PIN")
                                        .font(.title3.weight(.semibold))
                                }
                                .padding(.horizontal, 24)
                                .padding(.vertical, 16)
                            }
                            .buttonStyle(.bordered)
                            .tint(.white)
                        }
                    }
                }
            }
            }
        }
        .onAppear {
            startAnimations()
        }
        .onChange(of: alarmManager.state) { _ in
            startAnimations()
        }
    }

    // MARK: - Computed Properties

    private var iconName: String {
        alarmManager.state == .alarming ? "bell.badge.waveform.fill" : "exclamationmark.shield.fill"
    }

    private var iconColor: Color {
        alarmManager.state == .alarming ? .red : .yellow
    }

    private var titleText: String {
        alarmManager.state == .alarming ? "ALARM ACTIVE" : "UNAUTHORIZED ACCESS"
    }

    // MARK: - Animations

    private func startAnimations() {
        // Icon pulse animation
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            iconScale = alarmManager.state == .alarming ? 1.15 : 1.05
        }

        // Background pulse for alarm state
        if alarmManager.state == .alarming {
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                pulseOpacity = 0.6
            }
        }
    }

    // MARK: - Actions

    private func authenticateWithBiometrics() {
        alarmManager.attemptBiometricDisarm { success in
            if !success {
                withAnimation { showPINEntry = true }
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
    @State private var shake = false

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "number.square.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.blue)

                Text("Enter PIN")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
            }

            // PIN input field
            OverlaySecureTextField(text: $pin, placeholder: "PIN", onSubmit: validate)
                .frame(width: 180, height: 32)
                .offset(x: shake ? -10 : 0)

            // Error message
            if showError {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill")
                    Text("Incorrect PIN")
                }
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(.red)
            }

            // Action buttons
            HStack(spacing: 16) {
                Button {
                    withAnimation { isPresented = false }
                } label: {
                    Text("Cancel")
                        .font(.body.weight(.medium))
                        .frame(width: 80)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .tint(.gray)

                Button {
                    validate()
                } label: {
                    Text("Verify")
                        .font(.body.weight(.semibold))
                        .frame(width: 80)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }
        }
        .padding(32)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(.white.opacity(0.2), lineWidth: 1)
                }
        }
    }

    private func validate() {
        if alarmManager.attemptPINDisarm(pin) {
            withAnimation { isPresented = false }
        } else {
            showError = true
            pin = ""
            // Shake animation
            withAnimation(.default) {
                shake = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.default) {
                    shake = false
                }
            }
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
