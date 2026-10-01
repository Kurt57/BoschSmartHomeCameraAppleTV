import Foundation
import Testing
@testable import BoschCameraTV

struct HomeAssistantConfigurationTests {
    @Test(arguments: [
        ("192.168.1.10:8123", "http://192.168.1.10:8123"),
        ("http://homeassistant.local:8123/", "http://homeassistant.local:8123"),
        (" https://ha.example.com/lovelace/0 ", "https://ha.example.com"),
    ])
    func normalizesServerURL(input: String, expected: String) {
        #expect(HomeAssistantConfiguration.serverURL(from: input)?.absoluteString == expected)
    }

    @Test(arguments: ["", "rtsp://192.168.1.10", "http://"])
    func rejectsInvalidServerURL(input: String) {
        #expect(HomeAssistantConfiguration.serverURL(from: input) == nil)
    }

    @Test func buildsEndpointURLs() throws {
        let config = HomeAssistantConfiguration(serverURL: TestHomeAssistant.serverURL, accessToken: "t")

        #expect(config.statesURL.absoluteString == "http://192.168.1.10:8123/api/states")
        #expect(config.webSocketURL?.absoluteString == "ws://192.168.1.10:8123/api/websocket")
        #expect(config.absoluteURL(forPath: "/api/hls/abc/master_playlist.m3u8")?.absoluteString
            == "http://192.168.1.10:8123/api/hls/abc/master_playlist.m3u8")

        let secure = HomeAssistantConfiguration(serverURL: try #require(URL(string: "https://ha.example.com")), accessToken: "t")
        #expect(secure.webSocketURL?.absoluteString == "wss://ha.example.com/api/websocket")
    }

    @Test func requiresServerAndToken() {
        let isolated = IsolatedDefaults()
        #expect(TestHomeAssistant.configured(isolated.defaults).current() != nil)
        #expect(TestHomeAssistant.configured(isolated.defaults, token: nil).current() == nil)
        #expect(TestHomeAssistant.configured(isolated.defaults, token: "").current() == nil)

        let noServer = HomeAssistantConfigurationProvider(
            settings: SettingsStore(defaults: IsolatedDefaults().defaults),
            tokens: InMemoryTokenStore(token: "token")
        )
        #expect(noServer.current() == nil)
    }

    @Test func mapsErrorsToStreamErrors() {
        #expect(StreamError(classifying: HomeAssistantError.unauthorized) == .unauthorized)
        #expect(StreamError(classifying: HomeAssistantError.unreachable) == .homeAssistantUnreachable)
        #expect(StreamError(classifying: HomeAssistantError.commandFailed("x")) == .streamUnavailable(statusCode: nil))
        #expect(StreamError(classifying: HomeAssistantError.httpStatus(403)) == .unauthorized)
        #expect(HomeAssistantError.mapping(URLError(.cannotConnectToHost)) as? HomeAssistantError == .unreachable)
    }
}

struct HomeAssistantMessagesTests {
    @Test func extractsCameraEntitiesSortedByName() throws {
        let json = """
        [
          {"entity_id": "camera.bosch_garten", "state": "idle", "attributes": {"friendly_name": "Garten"}},
          {"entity_id": "light.flur", "state": "on", "attributes": {"friendly_name": "Flur"}},
          {"entity_id": "camera.bosch_eingang", "state": "streaming", "attributes": {"friendly_name": "Eingang"}},
          {"entity_id": "camera.ohne_name", "state": "idle", "attributes": {}}
        ]
        """
        let cameras = try HomeAssistantMessages.cameras(fromStatesJSON: Data(json.utf8))

        #expect(cameras.map(\.id) == ["camera.ohne_name", "camera.bosch_eingang", "camera.bosch_garten"])
        #expect(cameras.map(\.name) == ["camera.ohne_name", "Eingang", "Garten"])
        #expect(cameras.allSatisfy { $0.streamURL == nil && $0.isHomeAssistantEntity })
    }

    @Test func rejectsInvalidStatesJSON() {
        #expect(throws: HomeAssistantError.invalidResponse) {
            _ = try HomeAssistantMessages.cameras(fromStatesJSON: Data("{}".utf8))
        }
    }

    @Test func encodesCommands() {
        #expect(HomeAssistantMessages.authMessage(token: "abc") == #"{"access_token":"abc","type":"auth"}"#)
        #expect(HomeAssistantMessages.cameraStreamCommand(id: 1, entityID: "camera.bosch_garten")
            == #"{"entity_id":"camera.bosch_garten","id":1,"type":"camera\/stream"}"#)
    }

    @Test func readsStreamPathFromResult() throws {
        let message = try HomeAssistantMessages.decode(Data(
            #"{"id":1,"type":"result","success":true,"result":{"url":"/api/hls/abc/master_playlist.m3u8"}}"#.utf8
        ))

        #expect(try HomeAssistantMessages.streamPath(from: message) == "/api/hls/abc/master_playlist.m3u8")
    }

    @Test func reportsFailedCommand() throws {
        let message = try HomeAssistantMessages.decode(Data(
            #"{"id":1,"type":"result","success":false,"error":{"code":"start_stream_failed","message":"camera.bosch_garten does not support play stream service"}}"#.utf8
        ))

        #expect(throws: HomeAssistantError.commandFailed("camera.bosch_garten does not support play stream service")) {
            _ = try HomeAssistantMessages.streamPath(from: message)
        }
    }

    @Test func toleratesOtherResultShapes() throws {
        let auth = try HomeAssistantMessages.decode(Data(#"{"type":"auth_required","ha_version":"2026.9.0"}"#.utf8))
        let list = try HomeAssistantMessages.decode(Data(#"{"id":2,"type":"result","success":true,"result":[1,2]}"#.utf8))

        #expect(auth.type == "auth_required")
        #expect(list.result == nil)
    }
}

struct HomeAssistantProviderTests {
    let isolated = IsolatedDefaults()

    @Test func usesHomeAssistantWhenConfigured() async throws {
        let api = FakeHomeAssistantAPI(cameras: .success([TestHomeAssistant.entrance]))
        let configuration = TestHomeAssistant.configured(isolated.defaults)
        let provider = ActiveCameraProvider(
            local: StubCameraProvider([TestCameras.frontDoor]),
            homeAssistant: HomeAssistantCameraProvider(api: api, configuration: configuration),
            configuration: configuration
        )

        #expect(try await provider.cameras() == [TestHomeAssistant.entrance])
    }

    @Test func fallsBackToLocalConfiguration() async throws {
        let configuration = TestHomeAssistant.configured(isolated.defaults, token: nil)
        let provider = ActiveCameraProvider(
            local: StubCameraProvider([TestCameras.frontDoor]),
            homeAssistant: HomeAssistantCameraProvider(api: FakeHomeAssistantAPI(), configuration: configuration),
            configuration: configuration
        )

        #expect(try await provider.cameras() == [TestCameras.frontDoor])
    }

    @Test func requestsFreshURLForHomeAssistantCamera() async throws {
        let streamURL = try #require(URL(string: "http://192.168.1.10:8123/api/hls/abc/master_playlist.m3u8"))
        let api = FakeHomeAssistantAPI(stream: .success(streamURL))
        let resolver = CameraStreamURLResolver(api: api, configuration: TestHomeAssistant.configured(isolated.defaults))

        #expect(try await resolver.streamURL(for: TestHomeAssistant.entrance) == streamURL)
        #expect(try await resolver.streamURL(for: TestHomeAssistant.entrance) == streamURL)
        #expect(api.requestedEntities == ["camera.bosch_eingang", "camera.bosch_eingang"])
    }

    @Test func prefersConfiguredURL() async throws {
        let api = FakeHomeAssistantAPI()
        let resolver = CameraStreamURLResolver(api: api, configuration: TestHomeAssistant.configured(isolated.defaults))
        var camera = TestHomeAssistant.entrance
        camera.streamURL = URL(string: "http://192.168.1.10:1984/api/stream.m3u8?src=eingang")

        #expect(try await resolver.streamURL(for: camera) == camera.streamURL)
        #expect(api.requestedEntities.isEmpty)
    }

    @Test func failsWithoutURLOrConfiguration() async {
        let resolver = CameraStreamURLResolver(
            api: FakeHomeAssistantAPI(),
            configuration: TestHomeAssistant.configured(isolated.defaults, token: nil)
        )

        await #expect(throws: StreamError.missingStreamURL) {
            _ = try await resolver.streamURL(for: TestHomeAssistant.entrance)
        }
    }
}
