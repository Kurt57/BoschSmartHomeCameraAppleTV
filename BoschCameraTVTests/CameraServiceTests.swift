import Foundation
import Testing
@testable import BoschCameraTV

struct CameraServiceTests {
    let isolated = IsolatedDefaults()

    private func makeService(_ cameras: [Camera]) -> (CameraService, SettingsStore) {
        let settings = SettingsStore(defaults: isolated.defaults)
        return (CameraService(provider: StubCameraProvider(cameras), settings: settings), settings)
    }

    @Test func hidesDisabledCameras() async throws {
        let (service, _) = makeService([TestCameras.frontDoor, TestCameras.garage, TestCameras.garden])

        let cameras = try await service.cameras()

        #expect(cameras.map(\.id) == ["front-door", "garden"])
    }

    @Test func appliesStreamURLOverrides() async throws {
        let (service, settings) = makeService([TestCameras.frontDoor, TestCameras.garden])
        let override = try #require(URL(string: "https://ha.example.com/haustuer.m3u8"))
        settings.setStreamURLOverride(override, for: "front-door")

        let cameras = try await service.cameras()

        #expect(cameras[0].streamURL == override)
        #expect(cameras[1].streamURL == TestCameras.garden.streamURL)
    }

    @Test func configuredCamerasAreUnmodified() async throws {
        let (service, settings) = makeService([TestCameras.frontDoor, TestCameras.garage])
        settings.setStreamURLOverride(URL(string: "https://ha.example.com/x.m3u8"), for: "front-door")

        let cameras = try await service.configuredCameras()

        #expect(cameras == [TestCameras.frontDoor, TestCameras.garage])
    }

    @Test func dropsDuplicateIDs() async throws {
        var duplicate = TestCameras.frontDoor
        duplicate.name = "Doppelt"
        let (service, _) = makeService([TestCameras.frontDoor, duplicate, TestCameras.garden])

        let cameras = try await service.cameras()

        #expect(cameras.map(\.name) == ["Haustür", "Garten"])
    }

    @Test func propagatesProviderErrors() async {
        let settings = SettingsStore(defaults: isolated.defaults)
        let service = CameraService(provider: StubCameraProvider(error: StubError()), settings: settings)

        await #expect(throws: StubError.self) {
            try await service.cameras()
        }
    }
}
