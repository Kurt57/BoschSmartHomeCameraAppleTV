import Foundation

/// Ermittelt unmittelbar vor jedem (Re-)Connect die abspielbare Stream-URL einer Kamera.
///
/// Für lokal konfigurierte Kameras ist das einfach `camera.streamURL`. Home Assistant
/// vergibt für HLS-Streams dagegen kurzlebige URLs (`/api/hls/<token>/master_playlist.m3u8`),
/// die per WebSocket-Befehl `camera/stream` neu angefordert werden müssen. Ein späterer
/// `HomeAssistantStreamURLResolver` kann genau das hier implementieren – der Player
/// ruft den Resolver bei jedem Reconnect erneut auf.
protocol StreamURLResolving: Sendable {
    func streamURL(for camera: Camera) async throws -> URL
}

/// Verwendet die in der Konfiguration hinterlegte URL unverändert.
struct DirectStreamURLResolver: StreamURLResolving {
    func streamURL(for camera: Camera) async throws -> URL {
        guard let url = camera.streamURL else { throw StreamError.missingStreamURL }
        guard url.isSupportedStreamURL else { throw StreamError.invalidStreamURL }
        return url
    }
}
