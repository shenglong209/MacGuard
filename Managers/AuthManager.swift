// AuthManager.swift
// MacGuard - Anti-Theft Alarm for macOS
// Created: 2025-12-18

import LocalAuthentication
import Security

/// Proof the owner just authenticated. Only `AuthManager` can mint one (fileprivate init).
struct OwnerAuthentication {
    enum Method: String {
        case system = "Touch ID / password"
        case pin = "PIN"
    }

    let method: Method

    fileprivate init(_ method: Method) {
        self.method = method
    }
}

/// 4-8 ASCII digits.
struct PIN {
    static let allowedLengths = 4...8

    fileprivate let digits: String

    init?(_ raw: String) {
        guard Self.allowedLengths.contains(raw.count),
              raw.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        digits = raw
    }

    var weakness: PINWeakness? {
        let values = digits.compactMap(\.wholeNumberValue)
        let steps = Set(zip(values, values.dropFirst()).map { $1 - $0 })
        if digits == "1234" || digits == "12345" { return .luggage }
        if steps == [0] { return .repeated }
        if steps == [1] || steps == [-1] { return .sequence }
        if PINWeakness.wellKnown.contains(digits) { return .common }
        return nil
    }
}

/// A guessable PIN. Saving one takes a second confirmation.
enum PINWeakness: Equatable {
    /// 1234 / 12345 (Spaceballs)
    case luggage
    case repeated
    case sequence
    case common

    static let wellKnown: Set<String> = ["1212", "2580", "1122", "1313", "6969", "2000", "1004", "123123", "121212", "112233"]

    var message: String {
        switch self {
        case .luggage:
            return "“That's the kind of thing an idiot would have on his luggage!”"
        case .repeated: return "A repeated digit is one of the first PINs anyone tries."
        case .sequence: return "A straight run of digits is one of the first PINs anyone tries."
        case .common: return "This is one of the most common PINs."
        }
    }
}

enum PINVerification {
    case accepted(OwnerAuthentication)
    case rejected
    case lockedOut
    case noPINConfigured
}

/// After `freeAttempts` wrong guesses, each one locks out for 30 s, doubling (capped at ~8.5 h).
struct PINThrottle: Equatable, Codable {
    static let freeAttempts = 3
    static let baseLockout: TimeInterval = 30

    private(set) var failedAttempts = 0
    private(set) var lockedUntil: Date?

    func lockout(at now: Date) -> Date? {
        guard let lockedUntil, now < lockedUntil else { return nil }
        return lockedUntil
    }

    mutating func recordSuccess() {
        self = PINThrottle()
    }

    /// Returns the new lockout end, if one starts.
    mutating func recordFailure(at now: Date) -> Date? {
        failedAttempts += 1
        let excess = failedAttempts - Self.freeAttempts
        guard excess > 0 else { return nil }
        let until = now.addingTimeInterval(Self.baseLockout * pow(2, Double(min(excess - 1, 10))))
        lockedUntil = until
        return until
    }
}

/// Manages authentication for disarming the alarm (Touch ID / password + PIN fallback)
class AuthManager: ObservableObject {
    // MARK: - Published Properties

    @Published var hasBiometrics = false
    @Published var hasPIN = false

    // MARK: - Private Properties

    private let keychainService = "com.shenglong.macguard"
    private let keychainAccount = "userPIN"

    /// Persisted, so a relaunch doesn't reset the count; only a disarm does.
    @Published private var throttle: PINThrottle {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(throttle), forKey: Self.throttleKey) }
    }
    private static let throttleKey = "pinThrottle"

    func pinLockout(at now: Date) -> Date? {
        throttle.lockout(at: now)
    }


    // MARK: - Initialization

    init() {
        throttle = UserDefaults.standard.data(forKey: Self.throttleKey)
            .flatMap { try? JSONDecoder().decode(PINThrottle.self, from: $0) } ?? PINThrottle()
        checkBiometrics()
        hasPIN = pinExists()
    }

    // MARK: - System Authentication

    /// Check if biometric authentication is available (used for labelling)
    func checkBiometrics() {
        let context = LAContext()
        var error: NSError?
        hasBiometrics = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)

        if let error = error {
            logActivity(.system, "Biometrics not available: \(error.localizedDescription)")
        }
    }

    /// `.deviceOwnerAuthentication` falls back to the password, so a Mac without Touch ID can disarm.
    func authenticate(completion: @escaping (OwnerAuthentication?) -> Void) {
        pendingAuthentication?.invalidate()
        let context = LAContext()
        pendingAuthentication = context
        let reason = "Authenticate to disable MacGuard alarm"

        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
            DispatchQueue.main.async {
                completion(success ? OwnerAuthentication(.system) : nil)
            }
        }
    }

    private var pendingAuthentication: LAContext?

    func cancelPendingAuthentication() {
        pendingAuthentication?.invalidate()
        pendingAuthentication = nil
    }

    // MARK: - PIN Management

    /// Save PIN to Keychain
    /// - Returns: true if saved successfully
    @discardableResult
    func savePIN(_ pin: PIN) -> Bool {
        // Delete existing PIN first
        deletePIN()

        let status = SecItemAdd(pinQuery([
            kSecValueData as String: Data(pin.digits.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]), nil)
        hasPIN = status == errSecSuccess

        if hasPIN {
            logActivity(.system, "PIN saved to Keychain")
        } else {
            logActivity(.system, "Failed to save PIN: \(status)")
        }

        return hasPIN
    }

    /// The PIN item's identity plus `extra`.
    private func pinQuery(_ extra: [String: Any] = [:]) -> CFDictionary {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: keychainService,
         kSecAttrAccount as String: keychainAccount]
            .merging(extra) { $1 } as CFDictionary
    }

    /// Attributes only: reading the secret would prompt for keychain access at launch.
    private func pinExists() -> Bool {
        SecItemCopyMatching(pinQuery([kSecReturnAttributes as String: true, kSecMatchLimit as String: kSecMatchLimitOne]), nil) == errSecSuccess
    }

    private func retrievePIN() -> Data? {
        var result: AnyObject?
        guard SecItemCopyMatching(pinQuery([kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]), &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    /// Not parsed as a `PIN`: older versions saved non-digit PINs, which must keep working.
    func verifyPIN(_ input: String, now: Date = Date()) -> PINVerification {
        if throttle.lockout(at: now) != nil {
            return .lockedOut
        }
        guard let stored = retrievePIN() else { return .noPINConfigured }

        if Self.constantTimeEquals(stored, Data(input.utf8)) {
            throttle.recordSuccess()
            return .accepted(OwnerAuthentication(.pin))
        }

        let until = throttle.recordFailure(at: now)
        logActivity(.system, "Incorrect PIN (attempt \(throttle.failedAttempts))")
        return until == nil ? .rejected : .lockedOut
    }

    func resetPINAttempts() {
        guard throttle != PINThrottle() else { return }
        throttle = PINThrottle()
    }

    static func constantTimeEquals(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        return zip(a, b).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }

    /// Delete PIN from Keychain
    /// - Returns: true if deleted successfully
    @discardableResult
    func deletePIN() -> Bool {
        let status = SecItemDelete(pinQuery())
        if status == errSecSuccess || status == errSecItemNotFound {
            hasPIN = false
            logActivity(.system, "PIN deleted from Keychain")
            return true
        }
        return false
    }
}
