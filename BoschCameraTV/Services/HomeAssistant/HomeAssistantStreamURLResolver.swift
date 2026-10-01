import Foundation

/// Ermittelt die Stream-URL vor jedem (Re-)Connect:
/// 1. Ist eine URL hinterlegt (Konfigurationsdatei oder Einstellungen), wird sie verwendet.
/// 2. Sonst fordert die App für Home-Assistant-Kameras (`camera.*`) per `camera/stream`
///    eine frische HLS-URL an. Deren Token läuft ab – deshalb bei jedem Versuch neu.
struct CameraStreamURLResolver: StreamURLResolving {
    let api: any HomeAssistantAPI
    let configuration: HomeAssistantConfigurationProvider
    private let direct = DirectStreamURLResolver()

    init(api: any HomeAssistantAPI, configuration: HomeAssistantConfigurationProvider) {
        self.api = api
        self.configuration = configuration
    }

    func streamURL(for camera: Camera) async throws -> URL {
        if camera.streamURL != nil {
            return try await direct.streamURL(for: camera)
        }
        guard camera.isHomeAssistantEntity, let current = configuration.current() else {
            throw StreamError.missingStreamURL
        }
        return try await api.streamURL(forEntity: camera.id, configuration: current)
    }
}
