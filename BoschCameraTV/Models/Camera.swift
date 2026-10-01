import Foundation

/// Eine Kamera, deren Live-Stream die App anzeigen kann.
///
/// Das Modell ist bewusst unabhängig von der Datenquelle: Heute kommt es aus einer
/// lokalen JSON-Datei (`LocalCameraProvider`), später z. B. aus der Home-Assistant-API.
/// Für Home-Assistant-Kameras kann `streamURL` leer bleiben – die URL wird dann erst
/// beim Abspielen über einen `StreamURLResolving` ermittelt.
struct Camera: Identifiable, Hashable, Codable, Sendable {
    let id: String
    var name: String
    var streamURL: URL?
    var enabled: Bool

    init(id: String, name: String, streamURL: URL?, enabled: Bool = true) {
        self.id = id
        self.name = name
        self.streamURL = streamURL
        self.enabled = enabled
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, streamURL, enabled
    }

    /// Tolerantes Decoding, damit eine einzelne unvollständige Kamera nicht die ganze
    /// Konfiguration unbrauchbar macht: `enabled` ist standardmäßig `true`, ein fehlender
    /// Name fällt auf die ID zurück und eine leere URL wird zu `nil`.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        let decodedName = try container.decodeIfPresent(String.self, forKey: .name)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        name = (decodedName?.isEmpty == false ? decodedName : nil) ?? id
        let urlString = try container.decodeIfPresent(String.self, forKey: .streamURL)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        streamURL = urlString.flatMap { $0.isEmpty ? nil : URL(string: $0) }
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(streamURL?.absoluteString, forKey: .streamURL)
        try container.encode(enabled, forKey: .enabled)
    }
}

extension URL {
    /// `true`, wenn AVPlayer diese URL als Stream laden kann (http/https mit Host).
    /// RTSP o. Ä. wird von AVFoundation nicht unterstützt und muss über Home Assistant
    /// bzw. go2rtc als HLS bereitgestellt werden.
    var isSupportedStreamURL: Bool {
        guard let scheme = scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }
        guard let host = host(), !host.isEmpty else { return false }
        return true
    }

    /// Parst eine vom Benutzer eingegebene Stream-URL. Liefert `nil` für leere oder nicht
    /// unterstützte Eingaben.
    static func streamURL(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed), url.isSupportedStreamURL else {
            return nil
        }
        return url
    }
}
