import Foundation
import Testing
@testable import BoschCameraTV

struct SettingsStoreTests {
    let isolated = IsolatedDefaults()
    let store: SettingsStore

    init() {
        store = SettingsStore(defaults: isolated.defaults)
    }

    @Test func showsOverviewByDefault() {
        #expect(!store.autoOpenLastCamera)

        store.autoOpenLastCamera = true

        #expect(store.autoOpenLastCamera)
    }

    @Test func remembersLastCamera() {
        #expect(store.lastCameraID == nil)

        store.lastCameraID = "garden"

        #expect(SettingsStore(defaults: isolated.defaults).lastCameraID == "garden")
    }

    @Test func storesAndRemovesOverrides() throws {
        let url = try #require(URL(string: "http://homeassistant.local:8123/api/hls/x/master_playlist.m3u8"))

        store.setStreamURLOverride(url, for: "front-door")
        #expect(store.streamURLOverride(for: "front-door") == url)

        store.setStreamURLOverride(nil, for: "front-door")
        #expect(store.streamURLOverrides.isEmpty)
    }

    @Test func ignoresInvalidStoredOverrides() {
        isolated.defaults.set(
            ["front-door": "rtsp://192.168.1.20/stream", "garden": "https://ha.example.com/garten.m3u8"],
            forKey: SettingsStore.Key.streamURLOverrides
        )

        #expect(Array(store.streamURLOverrides.keys) == ["garden"])
    }

    @Test func removesAllOverrides() throws {
        let url = try #require(URL(string: "https://ha.example.com/a.m3u8"))
        store.setStreamURLOverride(url, for: "a")
        store.setStreamURLOverride(url, for: "b")

        store.removeAllStreamURLOverrides()

        #expect(store.streamURLOverrides.isEmpty)
    }
}
