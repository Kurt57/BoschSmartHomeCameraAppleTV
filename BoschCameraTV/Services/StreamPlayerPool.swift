import Foundation

/// Vergibt je Kamera einen Player und hält den Stream am Laufen, solange ihn eine
/// Ansicht braucht (Kachel auf der Startseite, Vollbild).
@MainActor
protocol StreamProviding: AnyObject {
    /// Player einer Kamera – wird pro Kamera nur einmal erzeugt und wiederverwendet.
    func player(for camera: Camera) -> any StreamPlaying
    /// Eine Ansicht braucht den Stream: starten, falls er nicht läuft.
    func acquire(_ camera: Camera)
    /// Eine Ansicht braucht den Stream nicht mehr. Gestoppt wird erst nach einer
    /// Karenzzeit, damit z. B. der Wechsel Vollbild ↔ Startseite ohne Neuaufbau klappt.
    func release(_ camera: Camera)
}

/// Pool von `StreamPlayer`n – einer pro Kamera, mit Nutzungszähler.
///
/// Weil die Startseite alle sichtbaren Streams bereits abspielt, übernimmt die
/// Vollbildansicht einen laufenden Stream ohne erneuten Verbindungsaufbau.
@MainActor
final class StreamPlayerPool: StreamProviding {
    private let makePlayer: @MainActor () -> any StreamPlaying
    private let linger: Duration
    private var players: [Camera.ID: any StreamPlaying] = [:]
    private var cameras: [Camera.ID: Camera] = [:]
    private var leaseCounts: [Camera.ID: Int] = [:]
    private var pendingStops: [Camera.ID: Task<Void, Never>] = [:]
    private var isSuspended = false

    init(linger: Duration = .seconds(30), makePlayer: @escaping @MainActor () -> any StreamPlaying) {
        self.linger = linger
        self.makePlayer = makePlayer
    }

    func player(for camera: Camera) -> any StreamPlaying {
        if let player = players[camera.id] { return player }
        let player = makePlayer()
        // Kacheln sind stumm; nur die Vollbildansicht schaltet den Ton ein.
        player.player.isMuted = true
        players[camera.id] = player
        return player
    }

    func acquire(_ camera: Camera) {
        cameras[camera.id] = camera
        leaseCounts[camera.id, default: 0] += 1
        pendingStops.removeValue(forKey: camera.id)?.cancel()
        guard !isSuspended else { return }
        startIfNeeded(camera)
    }

    func release(_ camera: Camera) {
        let count = max(leaseCounts[camera.id, default: 0] - 1, 0)
        leaseCounts[camera.id] = count
        guard count == 0 else { return }
        pendingStops[camera.id]?.cancel()
        let linger = linger
        let cameraID = camera.id
        pendingStops[cameraID] = Task { [weak self] in
            try? await Task.sleep(for: linger)
            guard !Task.isCancelled, let self, self.leaseCounts[cameraID, default: 0] == 0 else { return }
            self.pendingStops[cameraID] = nil
            self.players[cameraID]?.stop()
        }
    }

    /// App im Hintergrund: alle Streams beenden (Netzwerk und Decoder frei).
    func suspendAll() {
        isSuspended = true
        for task in pendingStops.values { task.cancel() }
        pendingStops.removeAll()
        for player in players.values where player.state != .idle {
            player.stop()
        }
    }

    /// App wieder aktiv: alle noch benötigten Streams neu starten.
    func resumeAll() {
        guard isSuspended else { return }
        isSuspended = false
        for (cameraID, count) in leaseCounts where count > 0 {
            if let camera = cameras[cameraID] {
                startIfNeeded(camera)
            }
        }
    }

    private func startIfNeeded(_ camera: Camera) {
        let player = player(for: camera)
        if let current = player.currentCamera, current != camera {
            // Konfiguration geändert (z. B. andere Stream-URL) → neu verbinden.
            player.start(camera)
            return
        }
        switch player.state {
        case .idle, .failed:
            player.start(camera)
        case .loading, .playing, .paused, .reconnecting:
            break
        }
    }
}
