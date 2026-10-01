import AVFoundation
import Foundation
@testable import BoschCameraTV

// MARK: - Kameras

enum TestCameras {
    static let frontDoor = Camera(
        id: "front-door",
        name: "Haustür",
        streamURL: URL(string: "http://homeassistant.local:8123/api/hls/token/master_playlist.m3u8")
    )
    static let garden = Camera(
        id: "garden",
        name: "Garten",
        streamURL: URL(string: "http://homeassistant.local:1984/api/stream.m3u8?src=garten")
    )
    static let garage = Camera(id: "garage", name: "Garage", streamURL: nil, enabled: false)
}

// MARK: - UserDefaults

/// Eigene UserDefaults-Suite je Test, damit Tests sich nicht gegenseitig beeinflussen.
final class IsolatedDefaults {
    let suiteName = "BoschCameraTVTests.\(UUID().uuidString)"
    let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

// MARK: - Provider

struct StubError: LocalizedError, Equatable {
    var errorDescription: String? { "Stub-Fehler" }
}

struct StubCameraProvider: CameraProvider {
    var result: Result<[Camera], StubError>

    init(_ cameras: [Camera]) {
        result = .success(cameras)
    }

    init(error: StubError) {
        result = .failure(error)
    }

    func cameras() async throws -> [Camera] {
        try result.get()
    }
}

// MARK: - Player

/// Ersetzt den echten `StreamPlayer` in ViewModel-Tests.
@MainActor
final class FakeStreamPlayer: StreamPlaying {
    enum Call: Equatable {
        case start(Camera.ID)
        case pause
        case resume
        case retry
        case stop
    }

    let player = AVPlayer()
    var state: PlayerState = .idle
    var loadingStage: LoadingStage = .connecting
    var currentCamera: Camera?
    var reconnectAttempt = 0
    var lastError: StreamError?
    var retryPolicy = RetryPolicy.default
    private(set) var calls: [Call] = []

    func start(_ camera: Camera) {
        calls.append(.start(camera.id))
        currentCamera = camera
        state = .loading
        loadingStage = .connecting
    }

    func pause() {
        calls.append(.pause)
        state = .paused
    }

    func resume() {
        calls.append(.resume)
        state = .playing
    }

    func retry() {
        calls.append(.retry)
        state = .loading
    }

    func stop() {
        calls.append(.stop)
        currentCamera = nil
        state = .idle
    }
}

// MARK: - Warten auf asynchrone Zustandswechsel

@MainActor
func waitUntil(timeout: Duration = .seconds(3), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !condition() {
        if ContinuousClock.now >= deadline { return false }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return true
}
