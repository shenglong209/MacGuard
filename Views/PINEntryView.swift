// PINEntryView.swift
// MacGuard - Anti-Theft Alarm for macOS
// Created: 2025-12-18

import SwiftUI

/// View for entering PIN to disarm alarm
struct PINEntryView: View {
    @Binding var isPresented: Bool
    @State private var enteredPIN = ""
    @State private var showError = false

    let authManager: AuthManager
    let onSuccess: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Enter PIN")
                .font(.headline)

            SecureField("PIN", text: $enteredPIN)
                .textFieldStyle(.roundedBorder)
                .frame(width: 150)
                .onSubmit { validatePIN() }

            if showError {
                Text("Incorrect PIN")
                    .foregroundColor(.red)
                    .font(.caption)
            }

            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                Button("Verify") {
                    validatePIN()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 250)
    }

    private func validatePIN() {
        if authManager.validatePIN(enteredPIN) {
            onSuccess()
            isPresented = false
        } else {
            showError = true
            enteredPIN = ""
        }
    }
}

/// View for setting up a new PIN
struct PINSetupView: View {
    @Binding var isPresented: Bool
    @State private var pin = ""
    @State private var confirmPIN = ""
    @State private var showError = false
    @State private var errorMessage = ""

    let authManager: AuthManager

    var body: some View {
        VStack(spacing: 16) {
            Text("Set Backup PIN")
                .font(.headline)

            SecureField("Enter PIN (4-8 digits)", text: $pin)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)

            SecureField("Confirm PIN", text: $confirmPIN)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)

            if showError {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                Button("Save") {
                    savePIN()
                }
                .buttonStyle(.borderedProminent)
                .disabled(pin.count < 4)
            }
        }
        .padding()
        .frame(width: 280)
    }

    private func savePIN() {
        // Validate PIN length
        guard pin.count >= 4, pin.count <= 8 else {
            errorMessage = "PIN must be 4-8 characters"
            showError = true
            return
        }

        // Check if PINs match
        guard pin == confirmPIN else {
            errorMessage = "PINs don't match"
            showError = true
            confirmPIN = ""
            return
        }

        // Save PIN
        if authManager.savePIN(pin) {
            isPresented = false
        } else {
            errorMessage = "Failed to save PIN"
            showError = true
        }
    }
}

#Preview("PIN Entry") {
    PINEntryView(
        isPresented: .constant(true),
        authManager: AuthManager(),
        onSuccess: {}
    )
}

#Preview("PIN Setup") {
    PINSetupView(
        isPresented: .constant(true),
        authManager: AuthManager()
    )
}
