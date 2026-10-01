import Foundation
import Security

enum KeychainError: Error, Equatable {
    case unexpectedStatus(OSStatus)
    case invalidData
}

/// Schlanker Wrapper um Generic-Password-Einträge der Keychain.
///
/// Vorgesehen für Geheimnisse wie den Home-Assistant Long-Lived Access Token – solche
/// Werte dürfen weder im Quellcode noch in `UserDefaults` landen.
struct KeychainStore: Sendable {
    let service: String

    init(service: String = Bundle.main.bundleIdentifier ?? "com.example.BoschCameraTV") {
        self.service = service
    }

    func data(for account: String) throws -> Data? {
        var query = baseQuery(for: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { throw KeychainError.invalidData }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func setData(_ data: Data, for account: String) throws {
        let query = baseQuery(for: account)
        let attributes = [kSecValueData as String: data] as [String: Any]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(addStatus) }
        default:
            throw KeychainError.unexpectedStatus(updateStatus)
        }
    }

    func removeValue(for account: String) throws {
        let status = SecItemDelete(baseQuery(for: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func string(for account: String) throws -> String? {
        guard let data = try data(for: account) else { return nil }
        guard let string = String(data: data, encoding: .utf8) else { throw KeychainError.invalidData }
        return string
    }

    func setString(_ string: String, for account: String) throws {
        try setData(Data(string.utf8), for: account)
    }

    private func baseQuery(for account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
