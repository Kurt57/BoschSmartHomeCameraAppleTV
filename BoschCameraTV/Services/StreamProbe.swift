import Foundation
import OSLog

enum StreamProbeResult: Equatable, Sendable {
    /// Server erreichbar, Stream-Ressource vorhanden.
    case reachable
    /// Keine Aussage möglich (z. B. ATS blockiert URLSession, AVFoundation darf aber laden).
    case inconclusive
}

/// Prüft vor dem Start von AVPlayer, ob der Server erreichbar ist und den Stream liefert.
///
/// AVPlayer meldet Fehler oft erst nach langen Timeouts und ohne klare Ursache. Die
/// Vorabprüfung trennt sauber zwischen „Keine Verbindung zu Home Assistant“
/// (Netzwerkfehler), „Zugriff verweigert“ (401/403) und „Stream nicht verfügbar“
/// (404/5xx) – und kostet im lokalen Netz nur einen Roundtrip.
protocol StreamProbing: Sendable {
    func probe(_ url: URL) async throws -> StreamProbeResult
}

struct HTTPStreamProbe: StreamProbing {
    private let session: URLSession

    init(timeout: TimeInterval = 15) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout * 2
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
    }

    func probe(_ url: URL) async throws -> StreamProbeResult {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        do {
            // Nur die Header abwarten; der Body (Playlist bzw. Video) wird nicht geladen.
            let (bytes, response) = try await session.bytes(for: request)
            bytes.task.cancel()
            guard let httpResponse = response as? HTTPURLResponse else { return .inconclusive }
            return try Self.evaluate(statusCode: httpResponse.statusCode)
        } catch let error as StreamError {
            throw error
        } catch {
            if Task.isCancelled { throw CancellationError() }
            let classified = StreamError(classifying: error)
            if classified == .insecureConnectionBlocked {
                // ATS-Ausnahmen für Medien (NSAllowsArbitraryLoadsForMedia) gelten nur für
                // AVFoundation – AVPlayer soll es in diesem Fall trotzdem versuchen.
                Log.network.notice("Vorabprüfung durch ATS blockiert – AVPlayer übernimmt")
                return .inconclusive
            }
            throw classified
        }
    }

    static func evaluate(statusCode: Int) throws -> StreamProbeResult {
        switch statusCode {
        case 200..<400:
            return .reachable
        case 401, 403:
            throw StreamError.unauthorized
        default:
            throw StreamError.streamUnavailable(statusCode: statusCode)
        }
    }
}
