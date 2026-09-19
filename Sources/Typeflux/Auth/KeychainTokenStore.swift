import Foundation
import os
import Security

/// Stores authentication tokens in the macOS Keychain.
enum KeychainTokenStore {
    private struct StoredToken: Codable {
        let token: String
        let expiresAt: Int
        let refreshToken: String?
    }

    static let service = "ai.gulu.app.typeflux.auth"
    static let legacyServices = [
        "ai.gulu.app.typeflux.auth.v2",
        "ai.gulu.app.typeflux.auth.v1"
    ]

    static var runtimeDerivedService: String {
        let environmentBundleID = ProcessInfo.processInfo.environment["TYPEFLUX_BUNDLE_IDENTIFIER"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let bundleID = environmentBundleID?.isEmpty == false
            ? environmentBundleID!
            : (Bundle.main.bundleIdentifier ?? "ai.gulu.app.typeflux")
        return "\(bundleID).auth"
    }

    static var serviceCandidates: [String] {
        let candidates = [service] + legacyServices + [runtimeDerivedService]
        var seen = Set<String>()
        return candidates.filter { candidate in
            seen.insert(candidate).inserted
        }
    }

    private static let tokenAccount = "session"
    private static let userProfileAccount = "userProfile"
    static let logger = Logger(subsystem: "ai.gulu.app.typeflux", category: "KeychainTokenStore")
    static let inMemoryLock = NSLock()
    static var inMemoryValues: [String: Data] = [:]
    static var useInMemoryStoreForTesting = false

    static var usesInMemoryStore: Bool {
        useInMemoryStoreForTesting
    }

    // MARK: - Token

    @discardableResult
    static func saveToken(_ token: String, expiresAt: Int, refreshToken: String? = nil) -> Bool {
        let storedToken = StoredToken(token: token, expiresAt: expiresAt, refreshToken: refreshToken)
        return setKeychainValue(storedToken, account: tokenAccount)
    }

    static func loadToken() -> (token: String, expiresAt: Int)? {
        guard let storedToken: StoredToken = getKeychainValue(account: tokenAccount) else {
            return nil
        }
        return (storedToken.token, storedToken.expiresAt)
    }

    static func loadRefreshToken() -> String? {
        let stored: StoredToken? = getKeychainValue(account: tokenAccount)
        return stored?.refreshToken
    }

    static func deleteToken() {
        deleteKeychainItem(account: tokenAccount)
    }

    static var isTokenValid: Bool {
        guard let stored = loadToken() else { return false }
        return stored.expiresAt > Int(Date().timeIntervalSince1970)
    }

    /// Returns true if the access token will expire within the given interval.
    static func isTokenExpiringSoon(within interval: TimeInterval = 7 * 24 * 3600) -> Bool {
        guard let stored = loadToken() else { return true }
        let threshold = Int(Date().timeIntervalSince1970 + interval)
        return stored.expiresAt < threshold
    }

    // MARK: - User Profile

    @discardableResult
    static func saveUserProfile(_ profile: UserProfile) -> Bool {
        setKeychainValue(profile, account: userProfileAccount)
    }

    static func loadUserProfile() -> UserProfile? {
        getKeychainValue(account: userProfileAccount)
    }

    static func deleteUserProfile() {
        deleteKeychainItem(account: userProfileAccount)
    }

    // MARK: - Clear All

    static func clearAll() {
        deleteToken()
        deleteUserProfile()
    }
}
