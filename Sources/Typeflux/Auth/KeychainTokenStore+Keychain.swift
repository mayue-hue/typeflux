import Foundation
import Security

extension KeychainTokenStore {
    // MARK: - Keychain Helpers

    @discardableResult
    static func setKeychainValue(_ value: some Encodable, account: String) -> Bool {
        guard let data = try? JSONEncoder().encode(value) else {
            logger.error("Failed to encode keychain value for account \(account, privacy: .public)")
            return false
        }

        if usesInMemoryStore {
            inMemoryLock.lock()
            inMemoryValues[account] = data
            inMemoryLock.unlock()
            return true
        }

        for query in writeMatchingQueries(service: service, account: account) {
            let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            if updateStatus == errSecSuccess {
                return true
            }
            if updateStatus != errSecItemNotFound {
                logger.error(
                    "Failed to update keychain account \(account, privacy: .public): \(describeStatus(updateStatus), privacy: .public)"
                )
            }
        }

        var addQuery = addQuery(service: service, account: account)
        addQuery[kSecValueData as String] = data

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecSuccess {
            return true
        }
        if addStatus == errSecDuplicateItem {
            logger.error(
                "Keychain account \(account, privacy: .public) already exists but update did not match; replacing stale item"
            )
            if replaceKeychainValue(data, account: account) || updateDuplicateKeychainValue(data, account: account) {
                return true
            }
            return false
        }
        logger.error(
            "Failed to add keychain account \(account, privacy: .public): \(describeStatus(addStatus), privacy: .public)"
        )
        return false
    }

    static func getKeychainValue<Value: Decodable>(account: String) -> Value? {
        if usesInMemoryStore {
            inMemoryLock.lock()
            let data = inMemoryValues[account]
            inMemoryLock.unlock()
            guard let data else { return nil }
            return try? JSONDecoder().decode(Value.self, from: data)
        }

        for candidateService in serviceCandidates {
            if let value: Value = getKeychainValue(account: account, service: candidateService) {
                if candidateService != service {
                    migrateLegacyItem(account: account, from: candidateService)
                }
                return value
            }
        }
        return nil
    }

    static func getKeychainValue<Value: Decodable>(account: String, service candidateService: String) -> Value? {
        let queries = readMatchingQueries(service: candidateService, account: account)

        var result: AnyObject?
        let status = copyFirstMatching(queries, result: &result)

        guard status == errSecSuccess else {
            if status != errSecItemNotFound {
                logger.error(
                    "Failed to load keychain account \(account, privacy: .public): \(describeStatus(status), privacy: .public)"
                )
            }
            return nil
        }
        guard let data = result as? Data else {
            logger.error("Loaded non-data keychain value for account \(account, privacy: .public)")
            return nil
        }
        guard let value = try? JSONDecoder().decode(Value.self, from: data) else {
            logger.error("Failed to decode keychain value for account \(account, privacy: .public)")
            return nil
        }
        return value
    }

    static func deleteKeychainItem(account: String) {
        if usesInMemoryStore {
            inMemoryLock.lock()
            inMemoryValues.removeValue(forKey: account)
            inMemoryLock.unlock()
            return
        }

        for candidateService in serviceCandidates {
            for query in deleteMatchingQueries(service: candidateService, account: account) {
                let status = SecItemDelete(query as CFDictionary)
                if status != errSecSuccess, status != errSecItemNotFound {
                    logger.error(
                        "Failed to delete keychain account \(account, privacy: .public): \(describeStatus(status), privacy: .public)"
                    )
                }
            }
        }
    }

    static func migrateLegacyItem(account: String, from legacyService: String) {
        let queries = readMatchingQueries(service: legacyService, account: account)

        var result: AnyObject?
        let status = copyFirstMatching(queries, result: &result)
        guard status == errSecSuccess, let data = result as? Data else { return }

        let primaryQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        var addQuery = primaryQuery
        addQuery[kSecValueData as String] = data

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecSuccess || addStatus == errSecDuplicateItem {
            logger.info(
                "Migrated keychain account \(account, privacy: .public) from legacy service \(legacyService, privacy: .public)"
            )
        } else {
            logger.error(
                "Failed to migrate keychain account \(account, privacy: .public): \(describeStatus(addStatus), privacy: .public)"
            )
        }
    }

    static func replaceKeychainValue(_ data: Data, account: String) -> Bool {
        deleteKeychainItem(account: account)

        var addQuery = addQuery(service: service, account: account)
        addQuery[kSecValueData as String] = data

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecSuccess {
            return true
        }
        logger.error(
            "Failed to replace keychain account \(account, privacy: .public): \(describeStatus(addStatus), privacy: .public)"
        )
        return false
    }

    static func updateDuplicateKeychainValue(_ data: Data, account: String) -> Bool {
        for query in writeMatchingQueries(service: service, account: account) {
            let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            if status == errSecSuccess {
                return true
            }
            if status != errSecItemNotFound {
                logger.error(
                    "Failed to update duplicate keychain account \(account, privacy: .public): \(describeStatus(status), privacy: .public)"
                )
            }
        }
        logger.error("Failed to update duplicate keychain account \(account, privacy: .public)")
        return false
    }

    static func copyFirstMatching(_ queries: [[String: Any]], result: inout AnyObject?) -> OSStatus {
        var lastStatus: OSStatus = errSecItemNotFound
        for query in queries {
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            if status == errSecSuccess {
                return status
            }
            lastStatus = status
        }
        return lastStatus
    }

    static func readMatchingQueries(service queryService: String, account: String) -> [[String: Any]] {
        searchQueries(service: queryService, account: account).map { query in
            var readQuery = query
            readQuery[kSecReturnData as String] = true
            readQuery[kSecMatchLimit as String] = kSecMatchLimitOne
            return readQuery
        }
    }

    static func writeMatchingQueries(service queryService: String, account: String) -> [[String: Any]] {
        searchQueries(service: queryService, account: account)
    }

    static func deleteMatchingQueries(service queryService: String, account: String) -> [[String: Any]] {
        searchQueries(service: queryService, account: account)
    }

    static func searchQueries(service queryService: String, account: String) -> [[String: Any]] {
        var nonSynchronizableQuery = addQuery(service: queryService, account: account)
        nonSynchronizableQuery[kSecAttrSynchronizable as String] = false

        return [
            addQuery(service: queryService, account: account),
            nonSynchronizableQuery
        ]
    }

    static func addQuery(service queryService: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: queryService,
            kSecAttrAccount as String: account
        ]
    }

    static func describeStatus(_ status: OSStatus) -> String {
        if let message = SecCopyErrorMessageString(status, nil) as String? {
            return "\(status) (\(message))"
        }
        return "\(status)"
    }
}
