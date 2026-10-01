import Foundation
import Testing
@testable import BoschCameraTV

@MainActor
struct PlayerViewModelTests {
    let streamPlayer = FakeStreamPlayer()
    let viewModel: PlayerViewModel

    init() {
        viewModel = PlayerViewModel(camera: TestCameras.frontDoor, streamPlayer: streamPlayer)
    }

    // MARK: Lebenszyklus

    @Test func startsStreamOnAppear() {
        viewModel.onAppear()

        #expect(streamPlayer.calls == [.start("front-door")])
        #expect(viewModel.overlay == .progress(title: "Verbinde…", detail: nil))
        #expect(viewModel.isInfoVisible)
    }

    @Test func stopsStreamOnDisappear() {
        viewModel.onAppear()

        viewModel.onDisappear()

        #expect(streamPlayer.calls == [.start("front-door"), .stop])
    }

    @Test func doesNotStopStreamOfAnotherCamera() {
        streamPlayer.start(TestCameras.garden)

        viewModel.onDisappear()

        #expect(streamPlayer.calls == [.start("garden")])
        #expect(viewModel.state == .idle)
    }

    @Test func stopsInBackgroundAndRestartsWhenActive() {
        viewModel.onAppear()
        streamPlayer.state = .playing

        viewModel.didEnterBackground()
        #expect(streamPlayer.calls.last == .stop)

        viewModel.didBecomeActive()
        #expect(streamPlayer.calls == [.start("front-door"), .stop, .start("front-door")])
    }

    @Test func ignoresActivationWithoutPriorBackground() {
        viewModel.onAppear()

        viewModel.didBecomeActive()

        #expect(streamPlayer.calls == [.start("front-door")])
    }

    // MARK: Fernbedienung

    @Test func togglePausesAndResumes() {
        viewModel.onAppear()
        streamPlayer.state = .playing

        viewModel.togglePlayPause()
        #expect(streamPlayer.calls.last == .pause)
        #expect(viewModel.overlay == .paused)

        viewModel.togglePlayPause()
        #expect(streamPlayer.calls.last == .resume)
        #expect(viewModel.overlay == .none)
    }

    @Test func toggleRetriesAfterFailure() {
        viewModel.onAppear()
        streamPlayer.state = .failed(.homeAssistantUnreachable)

        viewModel.togglePlayPause()

        #expect(streamPlayer.calls.last == .retry)
    }

    @Test func toggleIsIgnoredWhileLoading() {
        viewModel.onAppear()

        viewModel.togglePlayPause()

        #expect(streamPlayer.calls == [.start("front-door")])
    }

    // MARK: Overlay

    @Test func showsBufferingState() {
        viewModel.onAppear()
        streamPlayer.loadingStage = .buffering

        #expect(viewModel.overlay == .progress(title: "Stream wird geladen…", detail: nil))
    }

    @Test func showsReconnectAttemptAndReason() {
        viewModel.onAppear()
        streamPlayer.state = .reconnecting
        streamPlayer.reconnectAttempt = 2
        streamPlayer.lastError = .homeAssistantUnreachable

        #expect(viewModel.overlay == .progress(
            title: "Verbindung wird wiederhergestellt…",
            detail: "Keine Verbindung zu Home Assistant · Versuch 2 von 8"
        ))
    }

    @Test func showsFailure() {
        viewModel.onAppear()
        streamPlayer.state = .failed(.streamUnavailable(statusCode: 404))

        guard case .failure(let title, let message, let systemImage) = viewModel.overlay else {
            Issue.record("Fehler-Overlay erwartet")
            return
        }
        #expect(title == "Stream nicht verfügbar")
        #expect(message.contains("404"))
        #expect(systemImage == "video.slash")
        #expect(viewModel.isShowingFailure)
    }

    @Test func showsNothingWhilePlaying() {
        viewModel.onAppear()
        streamPlayer.state = .playing

        #expect(viewModel.overlay == .none)
        #expect(viewModel.isLive)
        #expect(!viewModel.isShowingFailure)
    }

    @Test func hidesInfoAfterDelay() async {
        let viewModel = PlayerViewModel(
            camera: TestCameras.frontDoor,
            streamPlayer: streamPlayer,
            infoDisplayDuration: .milliseconds(20)
        )

        viewModel.onAppear()
        #expect(viewModel.isInfoVisible)

        #expect(await waitUntil { !viewModel.isInfoVisible })
    }
}
