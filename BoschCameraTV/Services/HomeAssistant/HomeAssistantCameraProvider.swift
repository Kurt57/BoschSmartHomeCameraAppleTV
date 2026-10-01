import Foundation

/// Kameras aus Home Assistant: alle `camera.*`-Entitäten.
struct HomeAssistantCameraProvider: CameraProvider {
    let api: any HomeAssistantAPI
    let configuration: HomeAssistantConfigurationProvider

    func cameras() async throws -> [Camera] {
        guard let current = configuration.current() else { throw HomeAssistantError.notConfigured }
        return try await api.cameras(configuration: current)
    }
}

/// Wählt bei jedem Laden die Datenquelle: Home Assistant, sobald Server und Token
/// hinterlegt sind, sonst die lokale `Cameras.json`.
struct ActiveCameraProvider: CameraProvider {
    let local: any CameraProvider
    let homeAssistant: any CameraProvider
    let configuration: HomeAssistantConfigurationProvider

    func cameras() async throws -> [Camera] {
        if configuration.current() != nil {
            return try await homeAssistant.cameras()
        }
        return try await local.cameras()
    }
}
