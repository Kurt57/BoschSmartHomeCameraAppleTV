import Foundation
import Testing
@testable import BoschCameraTV

@MainActor
struct PlayerViewModelTests {
    let streams = FakeStreams()
    var streamPlayer: FakeStreamPlayer { streams.streamPlayer }
    let viewModel: PlayerViewModel

    init() {
        viewModel = PlayerViewModel(camera: TestCameras.frontDoor, streams: streams)
    }

    // MARK: Lebenszyklus

    @Test func acquiresStreamAndUnmutesOnAppear() {
        streamPlayer.player.isMuted = true

        viewModel.onAppear()

        #expect(streams.acquired == ["front-door"])
        #expect(streamPlayer.calls == [.start("front-door")])
        #expect(!streamPlayer.player.isMuted)
        #expect(viewModel.overlay == .progress(title: "Verbinde…", detail: nil))
        #expect(viewModel.isInfoVisible)
    }

    @Test func releasesAndMutesOnDisappear() {
        viewModel.onAppear()

        viewModel.onDisappear()

        #expect(streams.released == ["front-door"])
        #expect(streamPlayer.player.isMuted)
        #expect(!streamPlayer.calls.contains(.stop))
    }

    @Test func takesOverRunningStreamWithoutRestart() {
        streamPlayer.start(TestCameras.frontDoor)
        streamPlayer.state = .playing

        viewModel.onAppear()

        #expect(streamPlayer.calls == [.start("front-door")])
        #expect(viewModel.overlay == .none)
    }

    @Test func tileStaysMutedAndSkipsUnavailableCamera() {
        var offline = TestCameras.frontDoor
        offline.isAvailable = false
        let tile = PlayerViewModel(camera: offline, streams: streams, playsAudio: false)
        streamPlayer.player.isMuted = true

        tile.onAppear()

        #expect(streams.acquired.isEmpty)
        #expect(streamPlayer.player.isMuted)
        #expect(tile.compactStatus?.text == "Kamera nicht verfügbar")
    }

    @Test func showsIdleForOtherCamera() {
        streamPlayer.start(TestCameras.garden)

        #expect(viewModel.state == .idle)
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
            streams: streams,
            infoDisplayDuration: .milliseconds(20)
        )

        viewModel.onAppear()
        #expect(viewModel.isInfoVisible)

        #expect(await waitUntil { !viewModel.isInfoVisible })
    }
}
