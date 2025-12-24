// AuthManager.swift
// MacGuard - Anti-Theft Alarm for macOS
// Created: 2025-12-18

import LocalAuthentication
import Security

/// Manages authentication for disarming the alarm (Touch ID + PIN fallback)
class AuthManager: ObservableObject {
    // MARK: - Published Properties

    @Published var hasBiometrics = false
    @Published var hasPIN = false

    // MARK: - Private Properties

    private let keychainService = "com.shenglong.macguard"
    private let keychainAccount = "userPIN"

    // MARK: - Logging Helper

    private func log(_ category: ActivityLogCategory, _ message: String) {
        Task { @MainActor in
            ActivityLogManager.shared.log(category, message)
        }
    }

    // MARK: - Initialization

    init() {
        checkBiometrics()
        hasPIN = retrievePIN() != nil
    }

    // MARK: - Biometrics

    /// Check if biometric authentication is available
    func checkBiometrics() {
        let context = LAContext()
        var error: NSError?
        hasBiometrics = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)

        if let error = error {
            log(.system, "Biometrics not available: \(error.localizedDescription)")
        }
    }

    /// Authenticate using biometrics (Touch ID)
    /// - Parameter completion: Called with (success, error)
    func authenticateWithBiometrics(completion: @escaping (Bool, Error?) -> Void) {
        let context = LAContext()
        let reason = "Authenticate to disable MacGuard alarm"

        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, error in
            DispatchQueue.main.async {
                completion(success, error)
            }
        }
    }

    /// Authenticate using biometrics or system password as fallback
    /// - Parameter completion: Called with (success, error)
    func authenticateWithAny(completion: @escaping (Bool, Error?) -> Void) {
        let context = LAContext()
        let reason = "Authenticate to disable MacGuard alarm"

        // This allows password fallback when biometrics fail
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, error in
            DispatchQueue.main.async {
                completion(success, error)
            }
        }
    }

    // MARK: - PIN Management

    /// Save PIN to Keychain
    /// - Parameter pin: The PIN to save
    /// - Returns: true if saved successfully
    @discardableResult
    func savePIN(_ pin: String) -> Bool {
        // Delete existing PIN first
        deletePIN()

        guard let data = pin.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        hasPIN = status == errSecSuccess

        if hasPIN {
            log(.system, "PIN saved to Keychain")
        } else {
            log(.system, "Failed to save PIN: \(status)")
        }

        return hasPIN
    }

    /// Retrieve PIN from Keychain
    /// - Returns: The stored PIN or nil
    func retrievePIN() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let pin = String(data: data, encoding: .utf8) else {
            return nil
        }
        return pin
    }

    /// Validate entered PIN against stored PIN
    /// - Parameter input: The PIN to validate
    /// - Returns: true if PIN matches
    func validatePIN(_ input: String) -> Bool {
        guard let stored = retrievePIN() else { return false }
        return stored == input
    }

    /// Delete PIN from Keychain
    /// - Returns: true if deleted successfully
    @discardableResult
    func deletePIN() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound {
            hasPIN = false
            log(.system, "PIN deleted from Keychain")
            return true
        }
        return false
    }
}
