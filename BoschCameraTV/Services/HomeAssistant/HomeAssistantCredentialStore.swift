import Foundation

/// Vorbereitung für Phase 2 (Home-Assistant-Anbindung) – in Phase 1 noch nicht verdrahtet.
///
/// Geplanter Ablauf:
/// 1. Benutzer gibt Server-URL und Long-Lived Access Token in den Einstellungen ein.
/// 2. Die Server-URL landet in `UserDefaults`, das Token **ausschließlich** hier in der Keychain.
/// 3. Ein `HomeAssistantCameraProvider` (implementiert `CameraProvider`) liest
///    `GET /api/states` mit `Authorization: Bearer <token>` und bildet alle
///    `camera.*`-Entities auf `Camera` ab (`id` = entity_id, `name` = friendly_name).
/// 4. Ein `HomeAssistantStreamURLResolver` (implementiert `StreamURLResolving`) fordert
///    vor jedem (Re-)Connect per WebSocket-Befehl `camera/stream` eine frische HLS-URL an.
/// 5. In `AppDependencies.live()` werden `LocalCameraProvider`/`DirectStreamURLResolver`
///    gegen diese Implementierungen ausgetauscht – Views und ViewModels bleiben unverändert.
struct HomeAssistantCredentialStore: Sendable {
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
