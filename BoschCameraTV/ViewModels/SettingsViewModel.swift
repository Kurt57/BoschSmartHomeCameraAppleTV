import Foundation
import Observation
import OSLog

/// ViewModel der Einstellungen: Home-Assistant-Verbindung, Start-Verhalten und
/// Stream-URL-Overrides je Kamera.
@MainActor
@Observable
final class SettingsViewModel {
    struct Entry: Identifiable, Equatable {
        let id: Camera.ID
        let name: String
        let isEnabled: Bool
        /// URL aus der Konfigurationsdatei – dient als Platzhalter im Eingabefeld.
        let configuredURL: URL?
        let isHomeAssistantEntity: Bool
        var overrideText: String
        var validationMessage: String?
    }

    enum ConnectionStatus: Equatable {
        case unknown
        case testing
        case connected(cameraCount: Int)
        case failed(String)
    }

    static let invalidURLMessage = "Ungültige URL – erwartet wird http:// oder https:// (HLS, .m3u8)."
    static let invalidServerURLMessage = "Ungültige Adresse – z. B. http://192.168.1.10:8123"

    private(set) var entries: [Entry] = []
    private(set) var autoOpenLastCamera: Bool
    private(set) var loadErrorMessage: String?

    private(set) var serverURLText: String
    private(set) var serverURLValidationMessage: String?
    private(set) var hasStoredToken: Bool
    private(set) var tokenErrorMessage: String?
    private(set) var connectionStatus: ConnectionStatus = .unknown
    /// Wird bei jeder Änderung der Verbindung erhöht – die View lädt dann neu.
    private(set) var configurationRevision = 0

    private let cameraService: CameraService
    private let settings: SettingsStore
    private let homeAssistant: HomeAssistantConfigurationProvider
    private let api: any HomeAssistantAPI
    private let localConfigurationSummary: String

    init(
        cameraService: CameraService,
        settings: SettingsStore,
        homeAssistant: HomeAssistantConfigurationProvider,
        api: any HomeAssistantAPI,
        localConfigurationSummary: String
    ) {
        self.cameraService = cameraService
        self.settings = settings
        self.homeAssistant = homeAssistant
        self.api = api
        self.localConfigurationSummary = localConfigurationSummary
        autoOpenLastCamera = settings.autoOpenLastCamera
        serverURLText = settings.homeAssistantServerURL?.absoluteString ?? ""
        hasStoredToken = homeAssistant.hasStoredToken
    }

    var isHomeAssistantConfigured: Bool {
        homeAssistant.current() != nil
    }

    /// Aktive Datenquelle, z. B. „Home Assistant (192.168.1.10)“ oder „Cameras.json“.
    var configurationSummary: String {
        if let current = homeAssistant.current() {
            return "Home Assistant (\(current.serverURL.host() ?? current.serverURL.absoluteString))"
        }
        return localConfigurationSummary
    }

    func load() async {
        do {
            let cameras = try await cameraService.configuredCameras()
            let overrides = settings.streamURLOverrides
            entries = cameras.map { camera in
                Entry(
                    id: camera.id,
                    name: camera.name,
                    isEnabled: camera.enabled,
                    configuredURL: camera.streamURL,
                    isHomeAssistantEntity: camera.isHomeAssistantEntity,
                    overrideText: overrides[camera.id]?.absoluteString ?? "",
                    validationMessage: nil
                )
            }
            loadErrorMessage = nil
        } catch {
            entries = []
            loadErrorMessage = error.localizedDescription
        }
    }

    // MARK: Home Assistant

    func updateServerURL(_ text: String) {
        serverURLText = text
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            settings.homeAssistantServerURL = nil
            serverURLValidationMessage = nil
            connectionDidChange()
            return
        }
        guard let url = HomeAssistantConfiguration.serverURL(from: text) else {
            serverURLValidationMessage = Self.invalidServerURLMessage
            return
        }
        settings.homeAssistantServerURL = url
        serverURLText = url.absoluteString
        serverURLValidationMessage = nil
        Log.settings.info("Home-Assistant-Server gespeichert")
        connectionDidChange()
    }

    /// Speichert ein neues Token in der Keychain. Leere Eingaben ändern nichts.
    /// Leerzeichen und Zeilenumbrüche (z. B. aus dem Kopieren) werden entfernt.
    func saveToken(_ text: String) {
        let token = String(text.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) })
        guard !token.isEmpty else { return }
        do {
            try homeAssistant.tokens.setAccessToken(token)
            hasStoredToken = true
            tokenErrorMessage = nil
            Log.settings.info("Home-Assistant-Token in der Keychain gespeichert")
            connectionDidChange()
        } catch {
            tokenErrorMessage = "Das Token konnte nicht gespeichert werden."
            Log.settings.error("Token speichern fehlgeschlagen: \(String(describing: error), privacy: .public)")
        }
    }

    /// Entfernt Server-Adresse und Token – die App nutzt dann wieder `Cameras.json`.
    func disconnectHomeAssistant() {
        settings.homeAssistantServerURL = nil
        try? homeAssistant.tokens.removeAccessToken()
        serverURLText = ""
        serverURLValidationMessage = nil
        hasStoredToken = false
        Log.settings.info("Home-Assistant-Verbindung entfernt")
        connectionDidChange()
    }

    func testConnection() async {
        guard let current = homeAssistant.current() else {
            connectionStatus = .failed(HomeAssistantError.notConfigured.localizedDescription)
            return
        }
        connectionStatus = .testing
        do {
            let cameras = try await api.cameras(configuration: current)
            connectionStatus = .connected(cameraCount: cameras.count)
        } catch {
            connectionStatus = .failed(error.localizedDescription)
        }
    }

    private func connectionDidChange() {
        connectionStatus = .unknown
        configurationRevision += 1
    }

    // MARK: Start & Overrides

    func setAutoOpenLastCamera(_ isOn: Bool) {
        autoOpenLastCamera = isOn
        settings.autoOpenLastCamera = isOn
    }

    /// Übernimmt eine Eingabe: leer → Override entfernen, gültig → speichern,
    /// ungültig → nur Hinweis anzeigen (nichts wird gespeichert).
    func updateOverride(_ text: String, for cameraID: Camera.ID) {
        guard let index = entries.firstIndex(where: { $0.id == cameraID }) else { return }
        entries[index].overrideText = text

        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            settings.setStreamURLOverride(nil, for: cameraID)
            entries[index].validationMessage = nil
            Log.settings.info("Stream-URL-Override für \(cameraID, privacy: .public) entfernt")
            return
        }
        guard let url = URL.streamURL(from: text) else {
            entries[index].validationMessage = Self.invalidURLMessage
            return
        }
        settings.setStreamURLOverride(url, for: cameraID)
        entries[index].validationMessage = nil
        Log.settings.info("Stream-URL-Override für \(cameraID, privacy: .public) gespeichert")
    }

    func resetOverrides() {
        settings.removeAllStreamURLOverrides()
        for index in entries.indices {
            entries[index].overrideText = ""
            entries[index].validationMessage = nil
        }
        Log.settings.info("Alle Stream-URL-Overrides entfernt")
    }

    var hasOverrides: Bool {
        !settings.streamURLOverrides.isEmpty
    }
}
