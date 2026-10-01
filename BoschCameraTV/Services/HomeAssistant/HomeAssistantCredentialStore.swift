import Foundation

/// Speichert das langlebige Home-Assistant-Zugangs-Token in der Keychain –
/// nie in `UserDefaults` oder im Quellcode.
struct HomeAssistantCredentialStore: HomeAssistantTokenStoring {
    private static let tokenAccount = "home-assistant.long-lived-access-token"

    private let keychain: KeychainStore

    init(keychain: KeychainStore = KeychainStore()) {
        self.keychain = keychain
    }

    func accessToken() throws -> String? {
        try keychain.string(for: Self.tokenAccount)
    }

    func setAccessToken(_ token: String) throws {
        try keychain.setString(token, for: Self.tokenAccount)
    }

    func removeAccessToken() throws {
        try keychain.removeValue(for: Self.tokenAccount)
    }
}
