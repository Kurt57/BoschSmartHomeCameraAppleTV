import Foundation
import Testing
@testable import BoschCameraTV

struct LocalCameraProviderTests {
    @Test func decodesCameraList() async throws {
        let provider = LocalCameraProvider(data: Data(PreviewData.camerasJSON.utf8))

        let cameras = try await provider.cameras()

        #expect(cameras.map(\.id) == ["front-door", "garden", "garage"])
        #expect(cameras.map(\.name) == ["Haustür", "Garten", "Garage"])
        #expect(cameras[2].streamURL == nil)
    }

    @Test func rejectsNonArrayJSON() async {
        let provider = LocalCameraProvider(data: Data(#"{"id": "front-door"}"#.utf8))

        await #expect(throws: CameraConfigurationError.self) {
            try await provider.cameras()
        }
    }

    @Test func namesMissingRequiredField() async {
        let provider = LocalCameraProvider(data: Data(#"[{"name": "Ohne ID"}]"#.utf8))

        do {
            _ = try await provider.cameras()
            Issue.record("Fehler erwartet")
        } catch CameraConfigurationError.invalidFormat(let detail) {
            #expect(detail.contains("id"))
        } catch {
            Issue.record("Unerwarteter Fehler: \(error)")
        }
    }

    @Test func reportsMissingFile() async {
        let provider = LocalCameraProvider(fileURL: URL(fileURLWithPath: "/nicht/vorhanden/Cameras.json"))

        await #expect(throws: CameraConfigurationError.self) {
            try await provider.cameras()
        }
    }

    @Test func reportsMissingConfigurationInBundle() async {
        // Ein Bundle ohne Konfigurationsdateien (das Test-Bundle selbst).
        let provider = LocalCameraProvider(bundle: Bundle(for: BundleToken.self))

        #expect(provider.configurationURL == nil)
        await #expect(throws: CameraConfigurationError.fileNotFound) {
            try await provider.cameras()
        }
    }

    #if os(tvOS)
    @Test func bundledExampleConfigurationIsValid() async throws {
        let url = try #require(Bundle.main.url(forResource: LocalCameraProvider.exampleConfigurationName, withExtension: "json"))
        let provider = LocalCameraProvider(fileURL: url)

        #expect(provider.isUsingExampleConfiguration)
        let cameras = try await provider.cameras()
        #expect(cameras.map(\.name) == ["Haustür", "Garten", "Garage"])
    }
    #endif
}

private final class BundleToken {}
