import AVFoundation
import Observation
import OSLog

/// AVPlayer-basierter Player für Live-Kamerastreams (HLS).
///
/// Verantwortlich für
/// - genau **eine** `AVPlayer`-Instanz über die gesamte App-Laufzeit (Items werden getauscht),
/// - den Verbindungsaufbau: URL auflösen → Server prüfen → `AVPlayerItem` laden,
/// - Fehlererkennung: Item-Status, Wiedergabefehler, Stalls (Watchdog), Stream-Ende,
/// - automatische Reconnects mit exponentiellem Backoff (`RetryPolicy`),
/// - das saubere Freigeben von Items, KVO-Beobachtern und Notifications.
///
/// Callbacks von AVFoundation werden über eine Generationsnummer einem konkreten
/// Verbindungsversuch zugeordnet; Meldungen veralteter Versuche werden verworfen.
@MainActor
@Observable
final class StreamPlayer: StreamPlaying {
    let player: AVPlayer
    let retryPolicy: RetryPolicy

    private(set) var state: PlayerState = .idle
    private(set) var loadingStage: LoadingStage = .connecting
    private(set) var currentCamera: Camera?
    private(set) var reconnectAttempt = 0
    private(set) var lastError: StreamError?

    private let resolver: any StreamURLResolving
    private let probe: any StreamProbing
    private let loadTimeout: TimeInterval
    private let stallTimeout: TimeInterval
    private let resumeInPlaceLimit: TimeInterval
    private let targetLiveOffset: TimeInterval
    private let sleeper: @Sendable (TimeInterval) async throws -> Void

    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var connectionTask: Task<Void, Never>?
    @ObservationIgnored private var watchdogTask: Task<Void, Never>?
    @ObservationIgnored private var itemObservations: [NSKeyValueObservation] = []
    @ObservationIgnored private var notificationTokens: [any NSObjectProtocol] = []
    @ObservationIgnored private var timeControlObservation: NSKeyValueObservation?
    @ObservationIgnored private var pausedAt: ContinuousClock.Instant?

    /// - Parameters:
    ///   - loadTimeout: Maximale Zeit vom Laden des Items bis zum ersten Bild.
    ///   - stallTimeout: Maximale Pufferzeit während laufender Wiedergabe.
    ///   - resumeInPlaceLimit: Nach längerer Pause wird der Stream neu aufgebaut statt fortgesetzt.
    ///   - targetLiveOffset: Angestrebter Abstand zum Live-Rand in Sekunden (Latenz).
    ///   - sleeper: Injizierbares Warten (Backoff, Watchdog) – in Tests sofort.
    init(
        player: AVPlayer = AVPlayer(),
        resolver: any StreamURLResolving = DirectStreamURLResolver(),
        probe: any StreamProbing = HTTPStreamProbe(),
        retryPolicy: RetryPolicy = .default,
        loadTimeout: TimeInterval = 30,
        stallTimeout: TimeInterval = 15,
        resumeInPlaceLimit: TimeInterval = 30,
        targetLiveOffset: TimeInterval = 3,
        sleeper: @escaping @Sendable (TimeInterval) async throws -> Void = { seconds in
            try await Task.sleep(for: .seconds(seconds))
        }
    ) {
        self.player = player
        self.resolver = resolver
        self.probe = probe
        self.retryPolicy = retryPolicy
        self.loadTimeout = loadTimeout
        self.stallTimeout = stallTimeout
        self.resumeInPlaceLimit = resumeInPlaceLimit
        self.targetLiveOffset = targetLiveOffset
        self.sleeper = sleeper

        player.automaticallyWaitsToMinimizeStalling = true
        player.preventsDisplaySleepDuringVideoPlayback = true
        observeTimeControlStatus()
    }

    // MARK: - Steuerung

    func start(_ camera: Camera) {
        Log.player.info("Starte Stream für Kamera \(camera.id, privacy: .public)")
        connectionTask?.cancel()
        tearDownPlayback()
        currentCamera = camera
        reconnectAttempt = 0
        lastError = nil
        connect(to: camera, isReconnect: false)
    }

    func pause() {
        guard state == .playing else { return }
        cancelWatchdog()
        player.pause()
        pausedAt = .now
        state = .paused
        Log.player.info("Wiedergabe pausiert")
    }

    /// Setzt die Wiedergabe am Live-Rand fort. Nach langer Pause oder einem Fehler während
    /// der Pause wird der Stream komplett neu aufgebaut.
    func resume() {
        guard state == .paused, let camera = currentCamera else { return }
        let pausedFor = pausedAt.map { ContinuousClock.Instant.now - $0 } ?? .zero
        pausedAt = nil
        guard let item = player.currentItem,
              item.status != .failed,
              pausedFor < .seconds(resumeInPlaceLimit) else {
            Log.player.info("Pause zu lang oder Item ungültig – Stream wird neu aufgebaut")
            start(camera)
            return
        }
        state = .loading
        loadingStage = .buffering
        seekToLiveEdge(of: item)
        player.play()
        startWatchdog(timeout: loadTimeout, failure: .stalled)
        Log.player.info("Wiedergabe fortgesetzt")
    }

    func retry() {
        guard let camera = currentCamera else { return }
        start(camera)
    }

    /// Beendet die Wiedergabe vollständig und gibt Item und Beobachter frei.
    func stop() {
        if let camera = currentCamera {
            Log.player.info("Stoppe Stream für Kamera \(camera.id, privacy: .public)")
        }
        connectionTask?.cancel()
        connectionTask = nil
        tearDownPlayback()
        currentCamera = nil
        reconnectAttempt = 0
        lastError = nil
        loadingStage = .connecting
        state = .idle
    }

    // MARK: - Verbindungsaufbau

    private func connect(to camera: Camera, isReconnect: Bool) {
        generation &+= 1
        let generation = self.generation
        state = isReconnect ? .reconnecting : .loading
        loadingStage = .connecting
        connectionTask = Task { [weak self] in
            await self?.establishConnection(to: camera, generation: generation)
        }
    }

    private func establishConnection(to camera: Camera, generation: Int) async {
        do {
            let url = try await resolver.streamURL(for: camera)
            try Task.checkCancellation()
            let probeResult = try await probe.probe(url)
            try Task.checkCancellation()
            guard generation == self.generation else { return }
            if probeResult == .inconclusive {
                Log.network.notice("Vorabprüfung ohne Ergebnis – AVPlayer lädt direkt")
            }
            attachItem(for: url)
        } catch is CancellationError {
            Log.player.debug("Verbindungsaufbau abgebrochen")
        } catch {
            guard !Task.isCancelled else { return }
            handleFailure(StreamError(classifying: error), generation: generation)
        }
    }

    private func attachItem(for url: URL) {
        let item = AVPlayerItem(url: url)
        // Möglichst nah am Live-Rand starten (Standard wären mehrere Segmentlängen,
        // bei Home Assistant leicht 10 s und mehr) und diesen Abstand nach einem
        // Puffern wiederherstellen.
        item.configuredTimeOffsetFromLive = CMTime(seconds: targetLiveOffset, preferredTimescale: 1000)
        item.automaticallyPreservesTimeOffsetFromLive = true
        observe(item)
        loadingStage = .buffering
        player.replaceCurrentItem(with: item)
        player.play()
        startWatchdog(timeout: loadTimeout, failure: .stalled)
        Log.player.debug("AVPlayerItem geladen, warte auf erstes Bild")
    }

    // MARK: - Fehlerbehandlung & Reconnect

    private func handleFailure(_ error: StreamError, generation: Int) {
        guard generation == self.generation, let camera = currentCamera else { return }
        switch state {
        case .idle, .failed:
            return
        case .paused:
            // Kein Reconnect während einer Pause – `resume()` baut den Stream neu auf.
            lastError = error
            return
        case .loading, .playing, .reconnecting:
            break
        }

        Log.player.error("Stream-Fehler bei \(camera.id, privacy: .public): \(String(describing: error), privacy: .public)")
        lastError = error
        tearDownPlayback()

        guard error.isTransient, retryPolicy.canRetry(afterAttempts: reconnectAttempt) else {
            Log.player.error("Kein weiterer Reconnect (Versuche: \(self.reconnectAttempt))")
            state = .failed(error)
            return
        }
        scheduleReconnect(to: camera)
    }

    private func scheduleReconnect(to camera: Camera) {
        reconnectAttempt += 1
        let attempt = reconnectAttempt
        let delay = retryPolicy.delay(forAttempt: attempt)
        state = .reconnecting
        loadingStage = .connecting
        Log.player.info("Reconnect \(attempt)/\(self.retryPolicy.maximumAttempts) in \(Int(delay * 1000)) ms")

        let generation = self.generation
        let sleeper = self.sleeper
        connectionTask?.cancel()
        connectionTask = Task { [weak self] in
            do {
                try await sleeper(delay)
            } catch {
                return
            }
            guard let self, generation == self.generation else { return }
            self.connect(to: camera, isReconnect: true)
        }
    }

    // MARK: - Watchdog

    private func startWatchdog(timeout: TimeInterval, failure: StreamError) {
        watchdogTask?.cancel()
        let generation = self.generation
        let sleeper = self.sleeper
        watchdogTask = Task { [weak self] in
            do {
                try await sleeper(timeout)
            } catch {
                return
            }
            guard let self, generation == self.generation else { return }
            Log.player.notice("Watchdog: nach \(Int(timeout)) s kein Bild")
            self.handleFailure(failure, generation: generation)
        }
    }

    private func cancelWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = nil
    }

    // MARK: - Beobachtung von AVFoundation

    private func observeTimeControlStatus() {
        // KVO kann auf beliebigen Threads melden → explizit `@Sendable` und zurück auf den MainActor.
        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { @Sendable [weak self] _, _ in
            guard let self else { return }
            Task { @MainActor in
                self.timeControlStatusDidChange()
            }
        }
    }

    private func timeControlStatusDidChange() {
        // Immer den aktuellen Wert lesen – die KVO-Meldung kann bereits überholt sein.
        switch player.timeControlStatus {
        case .playing:
            guard player.currentItem != nil,
                  state == .loading || state == .reconnecting || state == .playing else { return }
            cancelWatchdog()
            if state != .playing {
                Log.player.info("Wiedergabe läuft")
            }
            state = .playing
            reconnectAttempt = 0
            lastError = nil
        case .waitingToPlayAtSpecifiedRate:
            guard state == .playing else { return }
            let reason = player.reasonForWaitingToPlay?.rawValue ?? "unbekannt"
            Log.player.notice("Wiedergabe puffert (\(reason, privacy: .public))")
            state = .loading
            loadingStage = .buffering
            startWatchdog(timeout: stallTimeout, failure: .stalled)
        case .paused:
            break
        @unknown default:
            break
        }
    }

    private func observe(_ item: AVPlayerItem) {
        let generation = self.generation

        // Status und Fehler werden erst auf dem MainActor am aktuellen Item gelesen.
        let statusObservation = item.observe(\.status, options: [.new]) { @Sendable [weak self] _, _ in
            guard let self else { return }
            Task { @MainActor in
                self.itemStatusDidChange(generation: generation)
            }
        }
        itemObservations = [statusObservation]

        let center = NotificationCenter.default
        notificationTokens = [
            center.addObserver(
                forName: AVPlayerItem.failedToPlayToEndTimeNotification,
                object: item,
                queue: .main
            ) { @Sendable [weak self] notification in
                let underlying = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? any Error
                let failure = underlying.map { StreamError(classifying: $0) } ?? .streamUnavailable(statusCode: nil)
                guard let self else { return }
                MainActor.assumeIsolated {
                    self.handleFailure(failure, generation: generation)
                }
            },
            center.addObserver(
                forName: AVPlayerItem.didPlayToEndTimeNotification,
                object: item,
                queue: .main
            ) { @Sendable [weak self] _ in
                guard let self else { return }
                MainActor.assumeIsolated {
                    self.handleFailure(.streamEnded, generation: generation)
                }
            },
            center.addObserver(
                forName: AVPlayerItem.playbackStalledNotification,
                object: item,
                queue: .main
            ) { @Sendable _ in
                Log.player.notice("AVPlayerItem meldet Stall")
            },
            center.addObserver(
                forName: AVPlayerItem.newErrorLogEntryNotification,
                object: item,
                queue: .main
            ) { @Sendable [weak self] _ in
                guard let self else { return }
                MainActor.assumeIsolated {
                    self.logLatestErrorLogEntry(generation: generation)
                }
            },
        ]
    }

    private func itemStatusDidChange(generation: Int) {
        guard generation == self.generation, let item = player.currentItem else { return }
        switch item.status {
        case .readyToPlay:
            Log.player.debug("AVPlayerItem bereit")
        case .failed:
            let failure = item.error.map { StreamError(classifying: $0) } ?? .streamUnavailable(statusCode: nil)
            handleFailure(failure, generation: generation)
        case .unknown:
            break
        @unknown default:
            break
        }
    }

    /// HLS-Fehlerlog (z. B. HTTP-Fehler einzelner Segmente) – nur zur Diagnose.
    private func logLatestErrorLogEntry(generation: Int) {
        guard generation == self.generation,
              let event = player.currentItem?.errorLog()?.events.last else { return }
        let domain = event.errorDomain
        let statusCode = event.errorStatusCode
        let comment = event.errorComment ?? "-"
        Log.player.notice("HLS-Fehlerlog: \(domain, privacy: .public) \(statusCode) – \(comment, privacy: .public)")
    }

    // MARK: - Aufräumen

    /// Entfernt Item, Beobachter und Watchdog. Durch das Erhöhen der Generation werden
    /// noch ausstehende Callbacks des alten Items wirkungslos.
    private func tearDownPlayback() {
        generation &+= 1
        cancelWatchdog()
        for observation in itemObservations {
            observation.invalidate()
        }
        itemObservations.removeAll()
        for token in notificationTokens {
            NotificationCenter.default.removeObserver(token)
        }
        notificationTokens.removeAll()
        if player.currentItem != nil {
            player.replaceCurrentItem(with: nil)
        }
        pausedAt = nil
    }

    private func seekToLiveEdge(of item: AVPlayerItem) {
        guard let liveRange = item.seekableTimeRanges.last?.timeRangeValue,
              liveRange.duration.isNumeric,
              liveRange.duration.seconds > 0 else { return }
        player.seek(to: liveRange.end)
    }
}
