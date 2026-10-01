import Foundation
import Testing
@testable import BoschCameraTV

@MainActor
struct SettingsViewModelTests {
    let isolated = IsolatedDefaults()
    let settings: SettingsStore
    let viewModel: SettingsViewModel

    init() {
        settings = SettingsStore(defaults: isolated.defaults)
        let service = CameraService(
            provider: StubCameraProvider([TestCameras.frontDoor, TestCameras.garage]),
            settings: settings
        )
        viewModel = SettingsViewModel(cameraService: service, settings: settings, configurationSummary: "Test")
    }

    @Test func listsAllConfiguredCameras() async {
        await viewModel.load()

        #expect(viewModel.entries.map(\.id) == ["front-door", "garage"])
        #expect(viewModel.entries[1].isEnabled == false)
        #expect(viewModel.entries[0].configuredURL == TestCameras.frontDoor.streamURL)
        #expect(viewModel.entries.allSatisfy { $0.overrideText.isEmpty })
    }

    @Test func showsExistingOverride() async {
        let override = URL(string: "https://ha.example.com/haustuer.m3u8")
        settings.setStreamURLOverride(override, for: "front-door")

        await viewModel.load()

        #expect(viewModel.entries[0].overrideText == "https://ha.example.com/haustuer.m3u8")
        #expect(viewModel.hasOverrides)
    }

    @Test func savesValidOverride() async {
        await viewModel.load()

        viewModel.updateOverride(" http://192.168.1.10:1984/api/stream.m3u8?src=haustuer ", for: "front-door")

        #expect(settings.streamURLOverride(for: "front-door")?.absoluteString == "http://192.168.1.10:1984/api/stream.m3u8?src=haustuer")
        #expect(viewModel.entries[0].validationMessage == nil)
    }

    @Test func rejectsInvalidOverride() async {
        await viewModel.load()

        viewModel.updateOverride("rtsp://192.168.1.20/stream", for: "front-door")

        #expect(settings.streamURLOverride(for: "front-door") == nil)
        #expect(viewModel.entries[0].validationMessage == SettingsViewModel.invalidURLMessage)
        #expect(viewModel.entries[0].overrideText == "rtsp://192.168.1.20/stream")
    }

    @Test func emptyInputRemovesOverride() async {
        settings.setStreamURLOverride(URL(string: "https://ha.example.com/a.m3u8"), for: "front-door")
        await viewModel.load()

        viewModel.updateOverride("", for: "front-door")

        #expect(settings.streamURLOverride(for: "front-door") == nil)
    }

    @Test func resetsAllOverrides() async {
        settings.setStreamURLOverride(URL(string: "https://ha.example.com/a.m3u8"), for: "front-door")
        await viewModel.load()

        viewModel.resetOverrides()

        #expect(settings.streamURLOverrides.isEmpty)
        #expect(viewModel.entries[0].overrideText.isEmpty)
        #expect(!viewModel.hasOverrides)
    }

    @Test func persistsAutoOpenSetting() {
        #expect(viewModel.autoOpenLastCamera)

        viewModel.setAutoOpenLastCamera(false)

        #expect(!viewModel.autoOpenLastCamera)
        #expect(!settings.autoOpenLastCamera)
    }
}
