import Foundation
import Observation
import OSLog

/// ViewModel der Einstellungen: Start-Verhalten und Stream-URL-Overrides je Kamera.
@MainActor
@Observable
final class SettingsViewModel {
    struct Entry: Identifiable, Equatable {
        let id: Camera.ID
        let name: String
        let isEnabled: Bool
        /// URL aus der Konfigurationsdatei – dient als Platzhalter im Eingabefeld.
        let configuredURL: URL?
        var overrideText: String
        var validationMessage: String?
    }

    static let invalidURLMessage = "Ungültige URL – erwartet wird http:// oder https:// (HLS, .m3u8)."

    private(set) var entries: [Entry] = []
    private(set) var autoOpenLastCamera: Bool
    private(set) var loadErrorMessage: String?
    /// Beschreibung der aktiven Datenquelle, z. B. „Cameras.json“.
    let configurationSummary: String

    private let cameraService: CameraService
    private let settings: SettingsStore

    init(cameraService: CameraService, settings: SettingsStore, configurationSummary: String) {
        self.cameraService = cameraService
        self.settings = settings
        self.configurationSummary = configurationSummary
        autoOpenLastCamera = settings.autoOpenLastCamera
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
