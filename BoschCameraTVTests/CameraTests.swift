import Foundation
import Testing
@testable import BoschCameraTV

struct CameraTests {
    @Test func decodesAllFields() throws {
        let json = #"{"id":"front-door","name":"Haustür","streamURL":"http://homeassistant.local:8123/api/hls/abc/master_playlist.m3u8","enabled":false}"#
        let camera = try JSONDecoder().decode(Camera.self, from: Data(json.utf8))

        #expect(camera.id == "front-door")
        #expect(camera.name == "Haustür")
        #expect(camera.streamURL?.host() == "homeassistant.local")
        #expect(camera.enabled == false)
    }

    @Test func appliesDefaultsForOptionalFields() throws {
        let camera = try JSONDecoder().decode(Camera.self, from: Data(#"{"id":"garage"}"#.utf8))

        #expect(camera.name == "garage")
        #expect(camera.streamURL == nil)
        #expect(camera.enabled)
    }

    @Test func treatsBlankURLAsMissing() throws {
        let json = #"{"id":"garage","name":"Garage","streamURL":"   "}"#
        let camera = try JSONDecoder().decode(Camera.self, from: Data(json.utf8))

        #expect(camera.streamURL == nil)
    }

    @Test func roundTripsThroughJSON() throws {
        let data = try JSONEncoder().encode(TestCameras.garden)
        let decoded = try JSONDecoder().decode(Camera.self, from: data)

        #expect(decoded == TestCameras.garden)
    }

    @Test(arguments: [
        ("http://homeassistant.local:8123/api/hls/x/master_playlist.m3u8", true),
        ("https://ha.example.com/stream.m3u8", true),
        ("  http://192.168.1.10:1984/api/stream.m3u8?src=garten  ", true),
        ("rtsp://192.168.1.20:554/stream", false),
        ("homeassistant.local:8123", false),
        ("", false),
    ])
    func validatesStreamURLs(input: String, isValid: Bool) {
        #expect((URL.streamURL(from: input) != nil) == isValid)
    }
}
