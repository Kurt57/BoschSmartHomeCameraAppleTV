import Foundation
import OSLog

/// Fassade, über die ViewModels Kameras beziehen.
///
/// Kapselt die austauschbare Datenquelle (`CameraProvider`) und wendet die
/// app-weiten Regeln an: doppelte IDs entfernen, deaktivierte Kameras ausblenden und
/// vom Benutzer gesetzte Stream-URLs (UserDefaults) berücksichtigen.
final class CameraService: Sendable {
    private let provider: any CameraProvider
    private let settings: SettingsStore

    init(provider: any CameraProvider, settings: SettingsStore) {
        self.provider = provider
        self.settings = settings
    }

    /// Aktivierte Kameras inkl. Stream-URL-Overrides – für die Kameraauswahl.
    func cameras() async throws -> [Camera] {
        let overrides = settings.streamURLOverrides
        return try await configuredCameras()
            .filter(\.enabled)
            .map { camera in
                guard let override = overrides[camera.id] else { return camera }
                var camera = camera
                camera.streamURL = override
                return camera
            }
    }

    /// Alle Kameras der Datenquelle (auch deaktivierte), ohne Overrides.
    func configuredCameras() async throws -> [Camera] {
        let cameras = try await provider.cameras()
        var seen = Set<Camera.ID>()
        return cameras.filter { camera in
            guard seen.insert(camera.id).inserted else {
                Log.cameras.warning("Doppelte Kamera-ID \(camera.id, privacy: .public) wird ignoriert")
                return false
            }
            return true
        }
    }
}
