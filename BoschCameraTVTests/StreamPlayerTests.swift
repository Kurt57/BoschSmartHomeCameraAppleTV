import AVFoundation
import Foundation
import Testing
@testable import BoschCameraTV

/// Testet Verbindungsaufbau, Fehlerklassifizierung und Reconnect-Logik des echten
/// `StreamPlayer` – ohne Netzwerk: Vorabprüfung und Wartezeiten sind ersetzt.
@MainActor
struct StreamPlayerTests {
    private static let fastRetries = RetryPolicy(
        initialDelay: 0.01, multiplier: 2, maximumDelay: 0.05, maximumAttempts: 2, jitterFraction: 0
    )

    private func makePlayer(probe: StubProbe, retryPolicy: RetryPolicy = StreamPlayerTests.fastRetries) -> StreamPlayer {
        StreamPlayer(
            resolver: DirectStreamURLResolver(),
            probe: probe,
            retryPolicy: retryPolicy,
            sleeper: { _ in await Task.yield() }
        )
    }

    @Test func startsIdle() {
        let player = makePlayer(probe: StubProbe(.reachable))

        #expect(player.state == .idle)
        #expect(player.currentCamera == nil)
    }

    @Test func failsImmediatelyWithoutStreamURL() async {
        let probe = StubProbe(.reachable)
        let player = makePlayer(probe: probe)

        player.start(Camera(id: "garage", name: "Garage", streamURL: nil))

        #expect(await waitUntil { player.state == .failed(.missingStreamURL) })
        #expect(await probe.callCount == 0)
        #expect(player.reconnectAttempt == 0)
    }

    @Test func rejectsUnsupportedScheme() async {
        let player = makePlayer(probe: StubProbe(.reachable))

        player.start(Camera(id: "rtsp", name: "RTSP", streamURL: URL(string: "rtsp://192.168.1.20/stream")))

        #expect(await waitUntil { player.state == .failed(.invalidStreamURL) })
    }

    @Test func doesNotRetryPermanentErrors() async {
        let probe = StubProbe(.failure(.unauthorized))
        let player = makePlayer(probe: probe)

        player.start(TestCameras.frontDoor)

        #expect(await waitUntil { player.state == .failed(.unauthorized) })
        #expect(await probe.callCount == 1)
    }

    @Test func reconnectsWithBackoffThenFails() async {
        let probe = StubProbe(.failure(.homeAssistantUnreachable))
        let player = makePlayer(probe: probe)

        player.start(TestCameras.frontDoor)

        #expect(await waitUntil { player.state == .failed(.homeAssistantUnreachable) })
        // Erster Versuch + zwei Reconnects laut RetryPolicy.
        #expect(await probe.callCount == 3)
        #expect(player.reconnectAttempt == 2)
        #expect(player.lastError == .homeAssistantUnreachable)
        #expect(player.currentCamera == TestCameras.frontDoor)
    }

    @Test func showsConnectingStageWhileProbing() async {
        let probe = StubProbe(.hang)
        let player = makePlayer(probe: probe)

        player.start(TestCameras.frontDoor)

        #expect(player.state == .loading)
        #expect(player.loadingStage == .connecting)
        #expect(await waitUntil { probe.hasStarted })
        player.stop()
    }

    @Test func stopCancelsPendingConnection() async {
        let probe = StubProbe(.hang)
        let player = makePlayer(probe: probe)
        player.start(TestCameras.frontDoor)
        #expect(await waitUntil { probe.hasStarted })

        player.stop()

        #expect(player.state == .idle)
        #expect(player.currentCamera == nil)
        #expect(player.player.currentItem == nil)
        #expect(await waitUntil { probe.wasCancelled })
        #expect(player.state == .idle)
    }

    @Test func retryStartsOverAfterFailure() async {
        let probe = StubProbe(.failure(.unauthorized))
        let player = makePlayer(probe: probe)
        player.start(TestCameras.frontDoor)
        #expect(await waitUntil { player.state == .failed(.unauthorized) })

        player.retry()

        #expect(player.state == .loading)
        #expect(await waitUntil { player.state == .failed(.unauthorized) })
        #expect(await probe.callCount == 2)
    }

    @Test func attachesPlayerItemAfterSuccessfulProbe() async {
        // Ohne Reconnects und mit langem Watchdog; die Adresse ist im Test nicht
        // erreichbar – geprüft wird nur der Übergang in die Pufferphase und das Freigeben.
        let player = StreamPlayer(
            resolver: DirectStreamURLResolver(),
            probe: StubProbe(.reachable),
            retryPolicy: RetryPolicy(initialDelay: 60, multiplier: 1, maximumDelay: 60, maximumAttempts: 0, jitterFraction: 0),
            loadTimeout: 60
        )

        player.start(TestCameras.frontDoor)

        #expect(await waitUntil { player.loadingStage == .buffering })

        player.stop()

        #expect(player.player.currentItem == nil)
        #expect(player.state == .idle)
        #expect(player.loadingStage == .connecting)
    }

    @Test func ignoresPauseWhenNotPlaying() {
        let player = makePlayer(probe: StubProbe(.hang))
        player.start(TestCameras.frontDoor)

        player.pause()

        #expect(player.state == .loading)
        player.stop()
    }
}

/// Ersetzt `HTTPStreamProbe`; zählt Aufrufe und kann hängen bleiben (bis zum Abbruch).
final class StubProbe: StreamProbing, @unchecked Sendable {
    enum Behavior: Sendable {
        case reachable
        case failure(StreamError)
        case hang
    }

    private let behavior: Behavior
    private let lock = NSLock()
    private var _callCount = 0
    private var _hasStarted = false
    private var _wasCancelled = false

    init(_ behavior: Behavior) {
        self.behavior = behavior
    }

    var callCount: Int {
        get async { lock.withLock { _callCount } }
    }

    var hasStarted: Bool {
        lock.withLock { _hasStarted }
    }

    var wasCancelled: Bool {
        lock.withLock { _wasCancelled }
    }

    func probe(_ url: URL) async throws -> StreamProbeResult {
        lock.withLock {
            _callCount += 1
            _hasStarted = true
        }
        switch behavior {
        case .reachable:
            return .reachable
        case .failure(let error):
            throw error
        case .hang:
            do {
                try await Task.sleep(for: .seconds(3600))
            } catch {
                lock.withLock { _wasCancelled = true }
                throw error
            }
            return .reachable
        }
    }
}
