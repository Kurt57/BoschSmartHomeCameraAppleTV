import Foundation

/// Zentrale Stelle, an der die konkreten Implementierungen zusammengesteckt werden.
///
/// Für die spätere Home-Assistant-Anbindung werden hier nur `LocalCameraProvider` und
/// `DirectStreamURLResolver` ausgetauscht – Views und ViewModels bleiben unverändert.
@MainActor
final class AppDependencies {
    let settings: SettingsStore
    let cameraService: CameraService
    /// Ein einziger Player für die gesamte App – er wird nie mehrfach erzeugt.
    let streamPlayer: StreamPlayer
    let configurationSummary: String

    init(settings: SettingsStore, cameraService: CameraService, streamPlayer: StreamPlayer, configurationSummary: String) {
        self.settings = settings
        self.cameraService = cameraService
        self.streamPlayer = streamPlayer
        self.configurationSummary = configurationSummary
    }

    static func live() -> AppDependencies {
        let settings = SettingsStore()
        let provider = LocalCameraProvider(bundle: .main)
        let summary: String
        if let url = provider.configurationURL {
            summary = provider.isUsingExampleConfiguration
                ? "\(url.lastPathComponent) (Beispiel – bitte Cameras.json anlegen)"
                : url.lastPathComponent
        } else {
            summary = "Keine Konfigurationsdatei gefunden"
        }
        return AppDependencies(
            settings: settings,
            cameraService: CameraService(provider: provider, settings: settings),
            streamPlayer: StreamPlayer(resolver: DirectStreamURLResolver(), probe: HTTPStreamProbe()),
            configurationSummary: summary
        )
    }
}
