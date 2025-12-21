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
    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Full-screen glass background
                FullScreenGlass()

                // Additional dark gradient for depth (less opaque with glass)
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.60), location: 0.0),
                        .init(color: .black.opacity(alarmManager.state == .alarming ? 0.40 : 0.50), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                // Pulsing background circle for alarm state - centered and fixed
                if alarmManager.state == .alarming {
                    Circle()
                        .fill(Theme.StateColor.alarming.opacity(pulseOpacity))
                        .frame(width: 350, height: 350)
                        .blur(radius: 80)
                        .scaleEffect(pulseScale)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                }

                // Main content card
                countdownCard
            }
        }
        .onAppear {
            startAnimations()
        }
        .onChange(of: alarmManager.state) { _ in
            startAnimations()
        }
    }

    // MARK: - Countdown Card

    private var countdownCard: some View {
        VStack(spacing: Theme.Spacing.xxl) {
            // Warning icon with glow
            warningIcon

            // Title
            Text(titleText)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .tracking(alarmManager.state == .alarming ? 4 : 2)

            // Countdown ring (triggered state)
            if alarmManager.state == .triggered {
                countdownRing

                Text("Authenticate to disarm")
                    .font(.body)
                    .foregroundStyle(.gray)
            }

            // Auth buttons or PIN entry
            if showPINEntry {
                PINOverlay(
                    isPresented: $showPINEntry,
                    alarmManager: alarmManager
                )
                .transition(.scale.combined(with: .opacity))
            } else {
                authButtons
            }
        }
        .padding(Theme.Spacing.xxxl + 16)
        .background {
            GlassBackground(
                material: .hudWindow,
                cornerRadius: Theme.CornerRadius.xxxl
            )
            .intenseShadow()
        }
    }

    // MARK: - Warning Icon

    private var warningIcon: some View {
        ZStack {
            // Glow effect
            Image(systemName: iconName)
                .font(.system(size: 90))
                .foregroundStyle(iconColor.opacity(0.6))
                .blur(radius: 25)

            // Main icon
            Image(systemName: iconName)
                .font(.system(size: 80))
                .foregroundStyle(iconColor)
                .symbolRenderingMode(.hierarchical)
        }
        .scaleEffect(iconScale)
    }

    // MARK: - Countdown Ring

    private var countdownRing: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: 8)
                .frame(width: 160, height: 160)

            // Progress ring
            Circle()
                .trim(from: 0, to: ringProgress)
                .stroke(
                    LinearGradient(
                        colors: [Theme.StateColor.alarming, Theme.StateColor.triggered],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .frame(width: 160, height: 160)
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: ringProgress)

            // Countdown number
            Text("\(alarmManager.countdownSeconds)")
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    private var ringProgress: CGFloat {
        guard AppSettings.shared.countdownDuration > 0 else { return 0 }
        return CGFloat(alarmManager.countdownSeconds) / CGFloat(AppSettings.shared.countdownDuration)
    }

    // MARK: - Auth Buttons

    private var authButtons: some View {
        VStack(spacing: Theme.Spacing.lg) {
            // Touch ID button (if available)
            if alarmManager.authManager.hasBiometrics {
                Button(action: authenticateWithBiometrics) {
                    HStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "touchid")
                            .font(.title2)
                        Text("Touch ID")
                            .font(.headline)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Spacing.xxl)
                    .padding(.vertical, Theme.Spacing.lg)
                }
                .buttonStyle(.plain)
                .background {
                    Capsule()
                        .fill(.clear)
                        .background(
                            VisualEffectView(
                                material: .hudWindow,
                                blendingMode: .withinWindow,
                                isEmphasized: true
                            )
                        )
                        .clipShape(Capsule())
                }
                .glassCapsuleBorder(prominent: true)
            }

            // PIN button
            if alarmManager.authManager.hasPIN {
                Button(action: { withAnimation { showPINEntry = true } }) {
                    HStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "number.square")
                            .font(.title3)
                        Text("Enter PIN")
                            .font(.headline)
                    }
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, Theme.Spacing.xl)
                    .padding(.vertical, Theme.Spacing.md)
                }
                .buttonStyle(.plain)
                .background {
                    Capsule()
                        .fill(.clear)
                        .background(
                            VisualEffectView(
                                material: .selection,
                                blendingMode: .withinWindow
                            )
                        )
                        .clipShape(Capsule())
                }
                .glassCapsuleBorder()
            }
        }
    }

    // MARK: - Computed Properties

    private var iconName: String {
        alarmManager.state == .alarming ? "bell.badge.waveform.fill" : "exclamationmark.shield.fill"
    }

    private var iconColor: Color {
        alarmManager.state == .alarming ? Theme.StateColor.alarming : Theme.StateColor.triggered
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
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                pulseOpacity = 0.6
                pulseScale = 1.1
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

/// PIN entry overlay with glass styling
struct PINOverlay: View {
    @Binding var isPresented: Bool
    @ObservedObject var alarmManager: AlarmStateManager

    @State private var pin = ""
    @State private var showError = false
    @State private var shakeOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            // Header
            VStack(spacing: Theme.Spacing.sm) {
                ZStack {
                    GlassIconCircle(size: 48, material: .selection)
                    Image(systemName: "number.square.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Theme.Accent.primary)
                }

                Text("Enter PIN")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
            }

            // PIN input field
            OverlaySecureTextField(text: $pin, placeholder: "PIN", onSubmit: validate)
                .frame(width: 180, height: 32)
                .offset(x: shakeOffset)

            // Error message
            if showError {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "xmark.circle.fill")
                    Text("Incorrect PIN")
                }
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(Theme.StateColor.alarming)
            }

            // Action buttons
            HStack(spacing: Theme.Spacing.lg) {
                Button {
                    withAnimation { isPresented = false }
                } label: {
                    Text("Cancel")
                        .font(.body.weight(.medium))
                        .frame(width: 80)
                }
                .buttonStyle(GlassSecondaryButtonStyle())

                Button {
                    validate()
                } label: {
                    Text("Verify")
                        .font(.body.weight(.semibold))
                        .frame(width: 80)
                }
                .buttonStyle(GlassBorderedProminentButtonStyle(tint: Theme.Accent.primary))
            }
        }
        .padding(Theme.Spacing.xxxl)
        .background {
            GlassBackground(
                material: .hudWindow,
                cornerRadius: Theme.CornerRadius.xxl
            )
            .modalShadow()
        }
    }

    private func validate() {
        if alarmManager.attemptPINDisarm(pin) {
            withAnimation { isPresented = false }
        } else {
            showError = true
            pin = ""
            // Shake animation
            withAnimation(.default.speed(2)) {
                shakeOffset = -10
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.default.speed(2)) {
                    shakeOffset = 10
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.default.speed(2)) {
                    shakeOffset = 0
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
