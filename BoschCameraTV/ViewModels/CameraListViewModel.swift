import Foundation
import Observation
import OSLog

/// ViewModel des Home-Screens „Meine Kameras“.
@MainActor
@Observable
final class CameraListViewModel {
    enum State: Equatable {
        case loading
        case loaded([Camera])
        case failed(message: String)
    }

    private(set) var state: State = .loading

    private let cameraService: CameraService
    private let settings: SettingsStore

    init(cameraService: CameraService, settings: SettingsStore) {
        self.cameraService = cameraService
        self.settings = settings
    }

    var cameras: [Camera] {
        guard case .loaded(let cameras) = state else { return [] }
        return cameras
    }

    var lastCameraID: String? {
        settings.lastCameraID
    }

    /// Kamera, die beim Erscheinen der Liste den Fokus erhält: die zuletzt genutzte,
    /// sonst die erste. So genügt ein Klick, um das gewohnte Bild zu öffnen.
    var preferredCameraID: Camera.ID? {
        let cameras = cameras
        if let lastID = settings.lastCameraID, cameras.contains(where: { $0.id == lastID }) {
            return lastID
        }
        return cameras.first?.id
    }

    func load() async {
        do {
            let cameras = try await cameraService.cameras()
            Log.cameras.info("\(cameras.count) Kamera(s) geladen")
            // Verfügbare Kameras zuerst – nicht verfügbare belegen keinen Platz oben.
            state = .loaded(cameras.filter(\.isAvailable) + cameras.filter { !$0.isAvailable })
        } catch {
            Log.cameras.error("Kameras konnten nicht geladen werden: \(error.localizedDescription, privacy: .public)")
            state = .failed(message: error.localizedDescription)
        }
    }

    func select(_ camera: Camera) {
        settings.lastCameraID = camera.id
    }

    /// Kamera, die beim App-Start ohne Umweg über die Liste geöffnet wird – damit
    /// möglichst schnell ein Kamerabild erscheint. `nil`, wenn deaktiviert oder unbekannt.
    func cameraForAutoOpen() -> Camera? {
        guard settings.autoOpenLastCamera, let lastID = settings.lastCameraID else { return nil }
        return cameras.first { $0.id == lastID }
    }
}
