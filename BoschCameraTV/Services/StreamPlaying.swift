import AVFoundation

/// Abstraktion des Stream-Players, damit `PlayerViewModel` ohne echtes Netzwerk und
/// ohne echte Wiedergabe getestet werden kann.
@MainActor
protocol StreamPlaying: AnyObject {
    /// Die eine, wiederverwendete AVPlayer-Instanz für die Videoausgabe.
    var player: AVPlayer { get }
    var state: PlayerState { get }
    var loadingStage: LoadingStage { get }
    /// Kamera, deren Stream gerade aktiv ist (auch während Reconnect und im Fehlerzustand).
    var currentCamera: Camera? { get }
    /// Nummer des laufenden Reconnect-Versuchs (0 = kein Reconnect).
    var reconnectAttempt: Int { get }
    /// Letzter aufgetretener Fehler – z. B. für die Anzeige während eines Reconnects.
    var lastError: StreamError? { get }
    var retryPolicy: RetryPolicy { get }

    func start(_ camera: Camera)
    func pause()
    func resume()
    func retry()
    func stop()
}
