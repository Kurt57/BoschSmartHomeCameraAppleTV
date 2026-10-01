import Foundation

/// Datenquelle für Kameras.
///
/// Heute: `LocalCameraProvider` (JSON-Datei im App-Bundle).
/// Später: z. B. ein `HomeAssistantCameraProvider`, der `camera.*`-Entities über
/// die Home-Assistant-REST-API (`GET /api/states`) ermittelt. Der Rest der App
/// arbeitet ausschließlich gegen dieses Protokoll.
protocol CameraProvider: Sendable {
    func cameras() async throws -> [Camera]
}
