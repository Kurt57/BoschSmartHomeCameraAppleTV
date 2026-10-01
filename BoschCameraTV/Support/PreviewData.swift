import Foundation

/// Beispieldaten für SwiftUI-Previews – enthalten bewusst keine echten Adressen.
enum PreviewData {
    static let camerasJSON = """
    [
      { "id": "front-door", "name": "Haustür", "streamURL": "http://homeassistant.local:8123/api/hls/PLATZHALTER/master_playlist.m3u8" },
      { "id": "garden", "name": "Garten", "streamURL": "http://homeassistant.local:8123/api/hls/PLATZHALTER/master_playlist.m3u8" },
      { "id": "garage", "name": "Garage", "streamURL": "" }
    ]
    """
}
