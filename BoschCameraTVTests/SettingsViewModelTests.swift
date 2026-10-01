import Foundation
import Testing
@testable import BoschCameraTV

@MainActor
struct SettingsViewModelTests {
    let isolated = IsolatedDefaults()
    let settings: SettingsStore
    let tokens = InMemoryTokenStore()
    let api = FakeHomeAssistantAPI(cameras: .success([TestHomeAssistant.entrance]))
    let viewModel: SettingsViewModel

    init() {
        settings = SettingsStore(defaults: isolated.defaults)
        let service = CameraService(
            provider: StubCameraProvider([TestCameras.frontDoor, TestCameras.garage]),
            settings: settings
        )
        viewModel = SettingsViewModel(
            cameraService: service,
            settings: settings,
            homeAssistant: HomeAssistantConfigurationProvider(settings: settings, tokens: tokens),
            api: api,
            localConfigurationSummary: "Cameras.json"
        )
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

    // MARK: Home Assistant

    @Test func storesServerAndTokenSeparately() throws {
        #expect(!viewModel.isHomeAssistantConfigured)
        #expect(viewModel.configurationSummary == "Cameras.json")

        viewModel.updateServerURL("192.168.1.10:8123")
        viewModel.saveToken("  geheimes-token  ")

        #expect(settings.homeAssistantServerURL == TestHomeAssistant.serverURL)
        #expect(try tokens.accessToken() == "geheimes-token")
        #expect(viewModel.serverURLText == "http://192.168.1.10:8123")
        #expect(viewModel.hasStoredToken)
        #expect(viewModel.isHomeAssistantConfigured)
        #expect(viewModel.configurationSummary == "Home Assistant (192.168.1.10)")
    }

    @Test func rejectsInvalidServerURL() {
        viewModel.updateServerURL("rtsp://192.168.1.10")

        #expect(viewModel.serverURLValidationMessage == SettingsViewModel.invalidServerURLMessage)
        #expect(settings.homeAssistantServerURL == nil)
    }

    @Test func removesLineBreaksFromPastedToken() throws {
        viewModel.saveToken("eyJhbGciOi\nJIUzI1NiJ9 .abc\r\n")

        #expect(try tokens.accessToken() == "eyJhbGciOiJIUzI1NiJ9.abc")
    }

    @Test func ignoresEmptyToken() throws {
        viewModel.saveToken("   ")

        #expect(try tokens.accessToken() == nil)
        #expect(!viewModel.hasStoredToken)
    }

    @Test func changesBumpRevisionForReload() {
        let before = viewModel.configurationRevision

        viewModel.updateServerURL("http://192.168.1.10:8123")
        viewModel.saveToken("token")

        #expect(viewModel.configurationRevision == before + 2)
    }

    @Test func testsConnection() async {
        viewModel.updateServerURL("http://192.168.1.10:8123")
        viewModel.saveToken("token")

        await viewModel.testConnection()

        #expect(viewModel.connectionStatus == .connected(cameraCount: 1))
    }

    @Test func reportsFailedConnectionTest() async {
        let failing = SettingsViewModel(
            cameraService: CameraService(provider: StubCameraProvider([]), settings: settings),
            settings: settings,
            homeAssistant: HomeAssistantConfigurationProvider(settings: settings, tokens: InMemoryTokenStore(token: "t")),
            api: FakeHomeAssistantAPI(cameras: .failure(.unauthorized)),
            localConfigurationSummary: "Cameras.json"
        )
        settings.homeAssistantServerURL = TestHomeAssistant.serverURL

        await failing.testConnection()

        #expect(failing.connectionStatus == .failed(HomeAssistantError.unauthorized.localizedDescription))
    }

    @Test func disconnectRemovesServerAndToken() throws {
        viewModel.updateServerURL("http://192.168.1.10:8123")
        viewModel.saveToken("token")

        viewModel.disconnectHomeAssistant()

        #expect(settings.homeAssistantServerURL == nil)
        #expect(try tokens.accessToken() == nil)
        #expect(!viewModel.isHomeAssistantConfigured)
    }
}
