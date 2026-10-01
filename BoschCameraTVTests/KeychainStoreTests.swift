import Foundation
import Testing
@testable import BoschCameraTV

struct KeychainStoreTests {
    let keychain = KeychainStore(service: "BoschCameraTVTests.\(UUID().uuidString)")
    let account = "test-account"

    @Test func storesUpdatesAndRemovesValues() throws {
        defer { try? keychain.removeValue(for: account) }

        #expect(try keychain.string(for: account) == nil)

        try keychain.setString("erstes-geheimnis", for: account)
        #expect(try keychain.string(for: account) == "erstes-geheimnis")

        try keychain.setString("zweites-geheimnis", for: account)
        #expect(try keychain.string(for: account) == "zweites-geheimnis")

        try keychain.removeValue(for: account)
        #expect(try keychain.string(for: account) == nil)
    }

    @Test func removingMissingValueSucceeds() throws {
        try keychain.removeValue(for: "nicht-vorhanden")
    }

    @Test func credentialStoreKeepsTokenInKeychain() throws {
        let store = HomeAssistantCredentialStore(keychain: keychain)
        defer { try? store.removeAccessToken() }

        try store.setAccessToken("long-lived-token")

        #expect(try store.accessToken() == "long-lived-token")
    }
}
