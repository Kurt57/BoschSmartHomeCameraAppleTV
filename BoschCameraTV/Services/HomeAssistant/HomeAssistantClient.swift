import Foundation
import OSLog

/// Zugriff auf Home Assistant – abstrahiert für Tests.
protocol HomeAssistantAPI: Sendable {
    /// Alle `camera.*`-Entitäten (REST `GET /api/states`).
    func cameras(configuration: HomeAssistantConfiguration) async throws -> [Camera]
    /// Frische HLS-URL einer Kamera-Entität (WebSocket-Befehl `camera/stream`).
    func streamURL(forEntity entityID: String, configuration: HomeAssistantConfiguration) async throws -> URL
}

/// URLSession-basierter Client für REST- und WebSocket-API von Home Assistant.
struct HomeAssistantClient: HomeAssistantAPI {
    private let session: URLSession
    private let requestTimeout: TimeInterval
    private let streamTimeout: TimeInterval

    /// - Parameter streamTimeout: Wartezeit auf `camera/stream`. Integrationen wie die
    ///   Bosch-Kamera öffnen dabei erst die Verbindung zur Kamera (typisch 10–20 s).
    init(requestTimeout: TimeInterval = 10, streamTimeout: TimeInterval = 60) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = streamTimeout
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
        self.requestTimeout = requestTimeout
        self.streamTimeout = streamTimeout
    }

    func cameras(configuration: HomeAssistantConfiguration) async throws -> [Camera] {
        var request = URLRequest(url: configuration.statesURL, timeoutInterval: requestTimeout)
        request.setValue("Bearer \(configuration.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw HomeAssistantError.mapping(error)
        }
        guard let httpResponse = response as? HTTPURLResponse else { throw HomeAssistantError.invalidResponse }
        switch httpResponse.statusCode {
        case 200..<300:
            let cameras = try HomeAssistantMessages.cameras(fromStatesJSON: data)
            Log.network.info("Home Assistant: \(cameras.count) Kamera-Entität(en) gefunden")
            return cameras
        case 401, 403:
            throw HomeAssistantError.unauthorized
        default:
            throw HomeAssistantError.httpStatus(httpResponse.statusCode)
        }
    }

    func streamURL(forEntity entityID: String, configuration: HomeAssistantConfiguration) async throws -> URL {
        guard let webSocketURL = configuration.webSocketURL else { throw HomeAssistantError.invalidServerURL }
        Log.network.info("Fordere Stream für \(entityID, privacy: .public) an")

        let task = session.webSocketTask(with: URLRequest(url: webSocketURL, timeoutInterval: streamTimeout))
        task.resume()
        defer { task.cancel(with: .normalClosure, reason: nil) }

        // Zeitlimit: Schließt den Socket, dadurch bricht das Warten auf Nachrichten ab.
        let timeout = streamTimeout
        let started = ContinuousClock.now
        let watchdog = Task {
            try? await Task.sleep(for: .seconds(timeout))
            if !Task.isCancelled {
                task.cancel(with: .goingAway, reason: nil)
            }
        }
        defer { watchdog.cancel() }

        let path: String
        do {
            path = try await withTaskCancellationHandler {
                try await Self.requestStreamPath(on: task, entityID: entityID, token: configuration.accessToken)
            } onCancel: {
                task.cancel(with: .goingAway, reason: nil)
            }
        } catch {
            if Task.isCancelled { throw CancellationError() }
            if ContinuousClock.now - started >= .seconds(timeout) { throw HomeAssistantError.timedOut }
            throw HomeAssistantError.mapping(error)
        }

        guard let url = configuration.absoluteURL(forPath: path) else { throw HomeAssistantError.invalidResponse }
        return url
    }

    private static func requestStreamPath(
        on task: URLSessionWebSocketTask,
        entityID: String,
        token: String
    ) async throws -> String {
        let hello = try await receive(from: task)
        guard hello.type == "auth_required" else { throw HomeAssistantError.invalidResponse }

        try await task.send(.string(HomeAssistantMessages.authMessage(token: token)))
        let auth = try await receive(from: task)
        switch auth.type {
        case "auth_ok":
            break
        case "auth_invalid":
            throw HomeAssistantError.unauthorized
        default:
            throw HomeAssistantError.invalidResponse
        }

        let commandID = 1
        try await task.send(.string(HomeAssistantMessages.cameraStreamCommand(id: commandID, entityID: entityID)))
        while true {
            let message = try await receive(from: task)
            guard message.type == "result", message.id == commandID else { continue }
            return try HomeAssistantMessages.streamPath(from: message)
        }
    }

    private static func receive(from task: URLSessionWebSocketTask) async throws -> HomeAssistantMessages.Message {
        switch try await task.receive() {
        case .string(let text):
            return try HomeAssistantMessages.decode(Data(text.utf8))
        case .data(let data):
            return try HomeAssistantMessages.decode(data)
        @unknown default:
            throw HomeAssistantError.invalidResponse
        }
    }
}
