import Foundation

/// Benutzereinstellungen in `UserDefaults`.
///
/// Hier landen nur unkritische Werte (zuletzt geöffnete Kamera, Stream-URL-Overrides).
/// Zugangsdaten wie ein Home-Assistant-Token gehören in die Keychain (`KeychainStore`).
///
/// Overrides lassen sich zum Testen auch per Launch-Argument setzen, z. B. im Xcode-Scheme:
/// `-streamURLOverrides '{ "front-door" = "http://homeassistant.local:8123/…"; }'`
final class SettingsStore: @unchecked Sendable {
    // `@unchecked`: `UserDefaults` ist laut Apple thread-safe; die Klasse hat keinen
    // eigenen veränderlichen Zustand.

    enum Key {
        static let lastCameraID = "lastCameraID"
        static let autoOpenLastCamera = "autoOpenLastCamera"
        static let streamURLOverrides = "streamURLOverrides"
        static let homeAssistantServerURL = "homeAssistantServerURL"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Key.autoOpenLastCamera: true])
    }

    /// ID der zuletzt geöffneten Kamera – wird beim Start fokussiert bzw. direkt geöffnet.
    var lastCameraID: String? {
        get { defaults.string(forKey: Key.lastCameraID) }
        set { defaults.set(newValue, forKey: Key.lastCameraID) }
    }

    /// Öffnet beim App-Start direkt die zuletzt verwendete Kamera.
    var autoOpenLastCamera: Bool {
        get { defaults.bool(forKey: Key.autoOpenLastCamera) }
        set { defaults.set(newValue, forKey: Key.autoOpenLastCamera) }
    }

    /// Adresse des Home-Assistant-Servers, z. B. `http://192.168.1.10:8123`.
    /// Das zugehörige Token liegt nicht hier, sondern in der Keychain.
    var homeAssistantServerURL: URL? {
        get { defaults.string(forKey: Key.homeAssistantServerURL).flatMap(HomeAssistantConfiguration.serverURL(from:)) }
        set { defaults.set(newValue?.absoluteString, forKey: Key.homeAssistantServerURL) }
    }

    /// Vom Benutzer gesetzte Stream-URLs je Kamera-ID. Ungültige Einträge werden ignoriert.
    var streamURLOverrides: [String: URL] {
        let raw = defaults.dictionary(forKey: Key.streamURLOverrides) as? [String: String] ?? [:]
        return raw.compactMapValues(URL.streamURL(from:))
    }

    func streamURLOverride(for cameraID: String) -> URL? {
        streamURLOverrides[cameraID]
    }

    /// Setzt bzw. entfernt (`nil`) den Override für eine Kamera.
    func setStreamURLOverride(_ url: URL?, for cameraID: String) {
        var raw = defaults.dictionary(forKey: Key.streamURLOverrides) as? [String: String] ?? [:]
        raw[cameraID] = url?.absoluteString
        if raw.isEmpty {
            defaults.removeObject(forKey: Key.streamURLOverrides)
        } else {
            defaults.set(raw, forKey: Key.streamURLOverrides)
        }
    }

    func removeAllStreamURLOverrides() {
        defaults.removeObject(forKey: Key.streamURLOverrides)
    }
}
