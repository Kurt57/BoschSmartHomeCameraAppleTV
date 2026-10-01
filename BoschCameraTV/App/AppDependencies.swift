import Foundation

/// Zentrale Stelle, an der die konkreten Implementierungen zusammengesteckt werden.
///
/// Kameraquelle: Home Assistant, sobald Server und Token eingerichtet sind, sonst die
/// lokale `Cameras.json`. Stream-URLs: hinterlegte URL oder frisch per `camera/stream`.
@MainActor
final class AppDependencies {
    let settings: SettingsStore
    let cameraService: CameraService
    /// Ein einziger Player für die gesamte App – er wird nie mehrfach erzeugt.
    let streamPlayer: StreamPlayer
    let homeAssistant: HomeAssistantConfigurationProvider
    let homeAssistantAPI: any HomeAssistantAPI
    /// Beschreibung der lokalen Konfigurationsdatei für die Einstellungen.
    let localConfigurationSummary: String

    init(
        settings: SettingsStore,
        cameraService: CameraService,
        streamPlayer: StreamPlayer,
        homeAssistant: HomeAssistantConfigurationProvider,
        homeAssistantAPI: any HomeAssistantAPI,
        localConfigurationSummary: String
    ) {
        self.settings = settings
        self.cameraService = cameraService
        self.streamPlayer = streamPlayer
        self.homeAssistant = homeAssistant
        self.homeAssistantAPI = homeAssistantAPI
        self.localConfigurationSummary = localConfigurationSummary
    }

    static func live() -> AppDependencies {
        let settings = SettingsStore()
        let homeAssistant = HomeAssistantConfigurationProvider(settings: settings, tokens: HomeAssistantCredentialStore())
        let api = HomeAssistantClient()

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
            streamPlayer: StreamPlayer(
                resolver: CameraStreamURLResolver(api: api, configuration: homeAssistant),
                probe: HTTPStreamProbe()
            ),
            homeAssistant: homeAssistant,
            homeAssistantAPI: api,
            localConfigurationSummary: summary
        )
    }
}
