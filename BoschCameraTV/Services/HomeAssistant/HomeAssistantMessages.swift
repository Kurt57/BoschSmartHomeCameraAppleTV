import Foundation

/// Kodierung und Auswertung der Home-Assistant-Nachrichten (REST und WebSocket).
/// Bewusst ohne Netzwerkcode, damit alles direkt testbar ist.
enum HomeAssistantMessages {
    // MARK: REST: GET /api/states

    private struct EntityState: Decodable {
        struct Attributes: Decodable {
            let friendlyName: String?
            let supportedFeatures: Int?

            private enum CodingKeys: String, CodingKey {
                case friendlyName = "friendly_name"
                case supportedFeatures = "supported_features"
            }
        }

        let entityID: String
        let state: String?
        let attributes: Attributes?

        private enum CodingKeys: String, CodingKey {
            case entityID = "entity_id"
            case state
            case attributes
        }
    }

    /// `CameraEntityFeature.STREAM` in Home Assistant.
    private static let streamFeature = 2

    /// Alle `camera.*`-Entitäten als Kameras, alphabetisch nach Namen. Die Stream-URL
    /// bleibt leer – sie wird beim Abspielen per `camera/stream` angefordert.
    ///
    /// Nicht verfügbar ist eine Kamera, wenn ihr Status `unavailable`/`unknown` ist oder
    /// sie kein Streaming anbietet (die Bosch-Integration nimmt das bei Offline-Kameras weg).
    static func cameras(fromStatesJSON data: Data) throws -> [Camera] {
        let states: [EntityState]
        do {
            states = try JSONDecoder().decode([EntityState].self, from: data)
        } catch {
            throw HomeAssistantError.invalidResponse
        }
        return states
            .filter { $0.entityID.hasPrefix(Camera.homeAssistantEntityPrefix) }
            .map { state in
                let name = state.attributes?.friendlyName?.trimmingCharacters(in: .whitespacesAndNewlines)
                let isOnline = state.state != "unavailable" && state.state != "unknown"
                let canStream = state.attributes?.supportedFeatures.map { $0 & streamFeature != 0 } ?? true
                return Camera(
                    id: state.entityID,
                    name: (name?.isEmpty == false ? name : nil) ?? state.entityID,
                    streamURL: nil,
                    isAvailable: isOnline && canStream
                )
            }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    // MARK: WebSocket

    struct Message: Decodable, Equatable {
        struct StreamResult: Decodable, Equatable {
            let url: String?
        }

        struct ErrorInfo: Decodable, Equatable {
            let code: String?
            let message: String?
        }

        let type: String
        let id: Int?
        let success: Bool?
        let result: StreamResult?
        let error: ErrorInfo?

        private enum CodingKeys: String, CodingKey {
            case type, id, success, result, error
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            type = try container.decode(String.self, forKey: .type)
            id = try container.decodeIfPresent(Int.self, forKey: .id)
            success = try container.decodeIfPresent(Bool.self, forKey: .success)
            // `result` hat je nach Befehl eine andere Form – nur die Stream-Antwort interessiert.
            result = try? container.decodeIfPresent(StreamResult.self, forKey: .result)
            error = try? container.decodeIfPresent(ErrorInfo.self, forKey: .error)
        }
    }

    static func decode(_ data: Data) throws -> Message {
        do {
            return try JSONDecoder().decode(Message.self, from: data)
        } catch {
            throw HomeAssistantError.invalidResponse
        }
    }

    static func authMessage(token: String) -> String {
        encode(["type": "auth", "access_token": token])
    }

    static func cameraStreamCommand(id: Int, entityID: String) -> String {
        struct Command: Encodable {
            let id: Int
            let type = "camera/stream"
            let entityID: String

            private enum CodingKeys: String, CodingKey {
                case id, type
                case entityID = "entity_id"
            }
        }
        return encode(Command(id: id, entityID: entityID))
    }

    /// Wertet die Antwort auf `camera/stream` aus und liefert den HLS-Pfad.
    static func streamPath(from message: Message) throws -> String {
        guard message.success == true else {
            throw HomeAssistantError.commandFailed(message.error?.message ?? message.error?.code ?? "unbekannter Fehler")
        }
        guard let url = message.result?.url, !url.isEmpty else {
            throw HomeAssistantError.invalidResponse
        }
        return url
    }

    private static func encode<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(value) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}
