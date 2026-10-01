import AVFoundation
import Observation

/// ViewModel der Wiedergabe einer Kamera – als Kachel auf der Startseite (stumm)
/// oder im Vollbild (mit Ton).
///
/// Übersetzt den Zustand des Kamera-Players in eine schlanke Darstellung für das
/// Overlay und kümmert sich um Fernbedienungs- und Lebenszyklus-Ereignisse. Den
/// Stream selbst hält der `StreamProviding`-Pool am Laufen.
@MainActor
@Observable
final class PlayerViewModel {
    /// Was über dem Videobild angezeigt wird – möglichst wenig.
    enum Overlay: Equatable {
        case none
        case progress(title: String, detail: String?)
        case paused
        case failure(title: String, message: String, systemImage: String)
    }

    enum Strings {
        static let connecting = "Verbinde…"
        static let loading = "Stream wird geladen…"
        static let reconnecting = "Verbindung wird wiederhergestellt…"
    }

    let camera: Camera
    private(set) var isInfoVisible = true

    private let streams: any StreamProviding
    private let streamPlayer: any StreamPlaying
    private let playsAudio: Bool
    private let infoDisplayDuration: Duration
    @ObservationIgnored private var infoTask: Task<Void, Never>?
    @ObservationIgnored private var isActive = false

    /// - Parameter playsAudio: `true` im Vollbild; Kacheln der Startseite bleiben stumm.
    init(
        camera: Camera,
        streams: any StreamProviding,
        playsAudio: Bool = true,
        infoDisplayDuration: Duration = .seconds(4)
    ) {
        self.camera = camera
        self.streams = streams
        self.streamPlayer = streams.player(for: camera)
        self.playsAudio = playsAudio
        self.infoDisplayDuration = infoDisplayDuration
    }

    var player: AVPlayer {
        streamPlayer.player
    }

    /// Zustand für diese Kamera. Spielt der geteilte Player gerade eine andere Kamera,
    /// gilt diese Ansicht als `idle`.
    var state: PlayerState {
        streamPlayer.currentCamera?.id == camera.id ? streamPlayer.state : .idle
    }

    /// Kurzer Status für Kacheln, z. B. „Verbinde…“; `nil` bei laufendem Bild.
    var compactStatus: (text: String, systemImage: String?)? {
        if !camera.isAvailable, state == .idle {
            return ("Kamera nicht verfügbar", "video.slash")
        }
        switch overlay {
        case .none:
            return nil
        case .paused:
            return ("Pausiert", "pause.fill")
        case .progress(let title, _):
            return (title, nil)
        case .failure(let title, _, let systemImage):
            return (title, systemImage)
        }
    }

    var isLive: Bool {
        state == .playing
    }

    var overlay: Overlay {
        switch state {
        case .idle:
            return .progress(title: Strings.connecting, detail: nil)
        case .loading:
            switch streamPlayer.loadingStage {
            case .connecting:
                return .progress(title: Strings.connecting, detail: nil)
            case .buffering:
                return .progress(title: Strings.loading, detail: nil)
            }
        case .playing:
            return .none
        case .paused:
            return .paused
        case .reconnecting:
            return .progress(title: Strings.reconnecting, detail: reconnectDetail)
        case .failed(let error):
            return .failure(title: error.title, message: error.message, systemImage: Self.systemImage(for: error))
        }
    }

    var isShowingFailure: Bool {
        guard case .failure = overlay else { return false }
        return true
    }

    private var reconnectDetail: String {
        var parts: [String] = []
        if let lastError = streamPlayer.lastError {
            parts.append(lastError.title)
        }
        let attempt = max(streamPlayer.reconnectAttempt, 1)
        parts.append("Versuch \(attempt) von \(streamPlayer.retryPolicy.maximumAttempts)")
        return parts.joined(separator: " · ")
    }

    // MARK: - Ereignisse aus der View

    /// Ansicht sichtbar: Stream anfordern (läuft er schon, wird er sofort übernommen).
    /// Kacheln nicht verfügbarer Kameras starten keinen Stream; im Vollbild wird es
    /// trotzdem versucht.
    func onAppear() {
        guard !isActive, camera.isAvailable || playsAudio else { return }
        isActive = true
        streams.acquire(camera)
        if playsAudio {
            streamPlayer.player.isMuted = false
        }
        showInfoTemporarily()
    }

    /// Ansicht verschwunden: Stream freigeben; der Pool stoppt ihn verzögert.
    func onDisappear() {
        guard isActive else { return }
        isActive = false
        infoTask?.cancel()
        if playsAudio {
            streamPlayer.player.isMuted = true
        }
        streams.release(camera)
    }

    /// Play/Pause-Taste bzw. Klick auf das Touchpad der Siri Remote.
    func togglePlayPause() {
        switch state {
        case .playing:
            streamPlayer.pause()
        case .paused:
            streamPlayer.resume()
        case .failed:
            streamPlayer.retry()
        case .idle:
            streamPlayer.start(camera)
        case .loading, .reconnecting:
            break
        }
        showInfoTemporarily()
    }

    func retry() {
        streamPlayer.start(camera)
        showInfoTemporarily()
    }

    /// Blendet Kameraname und Live-Status kurz ein.
    func showInfoTemporarily() {
        isInfoVisible = true
        infoTask?.cancel()
        let duration = infoDisplayDuration
        infoTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.isInfoVisible = false
        }
    }

    private static func systemImage(for error: StreamError) -> String {
        switch error {
        case .homeAssistantUnreachable:
            return "wifi.slash"
        case .streamUnavailable, .stalled, .streamEnded:
            return "video.slash"
        case .unauthorized:
            return "lock.fill"
        case .missingStreamURL, .invalidStreamURL, .insecureConnectionBlocked:
            return "exclamationmark.triangle.fill"
        }
    }
}
