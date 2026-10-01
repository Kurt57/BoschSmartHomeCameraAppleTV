import Foundation

/// Zentrale Stelle, an der die konkreten Implementierungen zusammengesteckt werden.
///
/// Kameraquelle: Home Assistant, sobald Server und Token eingerichtet sind, sonst die
/// lokale `Cameras.json`. Stream-URLs: hinterlegte URL oder frisch per `camera/stream`.
@MainActor
final class AppDependencies {
    let settings: SettingsStore
    let cameraService: CameraService
    /// Je Kamera genau ein Player, wiederverwendet zwischen Startseite und Vollbild.
    let streamPool: StreamPlayerPool
    let homeAssistant: HomeAssistantConfigurationProvider
    let homeAssistantAPI: any HomeAssistantAPI
    /// Beschreibung der lokalen Konfigurationsdatei für die Einstellungen.
    let localConfigurationSummary: String

    init(
        settings: SettingsStore,
        cameraService: CameraService,
        streamPool: StreamPlayerPool,
        homeAssistant: HomeAssistantConfigurationProvider,
        homeAssistantAPI: any HomeAssistantAPI,
        localConfigurationSummary: String
    ) {
        self.settings = settings
        self.cameraService = cameraService
        self.streamPool = streamPool
        self.homeAssistant = homeAssistant
        self.homeAssistantAPI = homeAssistantAPI
        self.localConfigurationSummary = localConfigurationSummary
    }

    static func live() -> AppDependencies {
        let settings = SettingsStore()
        let homeAssistant = HomeAssistantConfigurationProvider(settings: settings, tokens: HomeAssistantCredentialStore())
        let api = HomeAssistantClient()
        let probe = HTTPStreamProbe()

        let localProvider = LocalCameraProvider(bundle: .main)
        let provider = ActiveCameraProvider(
            local: localProvider,
            homeAssistant: HomeAssistantCameraProvider(api: api, configuration: homeAssistant),
            configuration: homeAssistant
        )

        let summary: String
        if let url = localProvider.configurationURL {
            summary = localProvider.isUsingExampleConfiguration
                ? "\(url.lastPathComponent) (Beispiel)"
                : url.lastPathComponent
        } else {
            summary = "Keine Konfigurationsdatei gefunden"
        }

        return AppDependencies(
            settings: settings,
            cameraService: CameraService(provider: provider, settings: settings),
            streamPool: StreamPlayerPool {
                StreamPlayer(
                    resolver: CameraStreamURLResolver(api: api, configuration: homeAssistant),
                    probe: probe
                )
            },
            homeAssistant: homeAssistant,
            homeAssistantAPI: api,
            localConfigurationSummary: summary
        )
    }
}
