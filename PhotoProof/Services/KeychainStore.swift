// KeychainStore.swift
// Stores the Immich API key in the user's login keychain as a generic password.
// The key is never written to UserDefaults, plist, or any file on disk.

import Foundation
import Security

enum KeychainError: Error, LocalizedError {
    case unexpectedStatus(OSStatus)
    case dataConversionFailed

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            if let msg = SecCopyErrorMessageString(status, nil) as String? {
                return "Keychain error \(status): \(msg)"
            }
            return "Keychain error \(status)"
        case .dataConversionFailed:
            return "Couldn't read the keychain entry as text."
        }
    }
}

final class KeychainStore {
    static let shared = KeychainStore()

    private let service = "com.carlmercier.PhotoProof.immich-api-key"
    private let account = "default"

    private init() {}

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func save(_ apiKey: String) throws {
        guard let data = apiKey.data(using: .utf8) else {
            throw KeychainError.dataConversionFailed
        }
        let query = baseQuery() as CFDictionary
        let attrs = [kSecValueData as String: data] as CFDictionary

        let updateStatus = SecItemUpdate(query, attrs)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = baseQuery()
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(addStatus)
            }
        default:
            throw KeychainError.unexpectedStatus(updateStatus)
        }
    }

    func read() throws -> String {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
        guard let data = result as? Data, let s = String(data: data, encoding: .utf8) else {
            throw KeychainError.dataConversionFailed
        }
        return s
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func exists() -> Bool {
        var query = baseQuery()
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }
}
