import Foundation

/// Fachliche Fehler beim Abspielen eines Kamera-Streams.
///
/// Rohe Fehler aus URLSession/AVFoundation werden über `init(classifying:)` auf diese
/// Fälle abgebildet. Daraus leiten sich Retry-Verhalten (`isTransient`) und die
/// Texte für die UI ab.
enum StreamError: Error, Equatable, Sendable {
    /// Für die Kamera ist keine Stream-URL hinterlegt.
    case missingStreamURL
    /// Die URL ist kein gültiger http(s)-Stream (z. B. `rtsp://`).
    case invalidStreamURL
    /// App Transport Security blockiert eine unverschlüsselte Verbindung.
    case insecureConnectionBlocked
    /// Home Assistant (bzw. der Stream-Server) ist nicht erreichbar.
    case homeAssistantUnreachable
    /// Der Server verweigert den Zugriff (HTTP 401/403).
    case unauthorized
    /// Der Server ist erreichbar, liefert den Stream aber nicht (z. B. HTTP 404/5xx,
    /// Kamera offline, ungültige Playlist). `statusCode` ist gesetzt, wenn bekannt.
    case streamUnavailable(statusCode: Int?)
    /// Der Stream liefert über längere Zeit keine Daten mehr.
    case stalled
    /// Der Live-Stream wurde serverseitig beendet.
    case streamEnded

    /// Temporäre Fehler werden automatisch mit Backoff erneut versucht.
    var isTransient: Bool {
        switch self {
        case .homeAssistantUnreachable, .streamUnavailable, .stalled, .streamEnded:
            return true
        case .missingStreamURL, .invalidStreamURL, .insecureConnectionBlocked, .unauthorized:
            return false
        }
    }

    /// Kurzer, für den Fernseher geeigneter Titel.
    var title: String {
        switch self {
        case .homeAssistantUnreachable:
            return "Keine Verbindung zu Home Assistant"
        case .streamUnavailable, .stalled, .streamEnded:
            return "Stream nicht verfügbar"
        case .unauthorized:
            return "Zugriff verweigert"
        case .missingStreamURL:
            return "Keine Stream-URL konfiguriert"
        case .invalidStreamURL:
            return "Ungültige Stream-URL"
        case .insecureConnectionBlocked:
            return "Unsichere Verbindung blockiert"
        }
    }

    /// Erklärung mit Handlungsempfehlung.
    var message: String {
        switch self {
        case .homeAssistantUnreachable:
            return "Der Server ist nicht erreichbar. Prüfe, ob Home Assistant läuft und sich das Apple TV im selben Netzwerk befindet."
        case .streamUnavailable(let statusCode?):
            return "Home Assistant ist erreichbar, liefert den Stream aber nicht (HTTP \(statusCode)). Ist die Kamera online und die Stream-URL aktuell?"
        case .streamUnavailable(.none):
            return "Home Assistant ist erreichbar, der Stream kann aber nicht abgespielt werden. Ist die Kamera online und liefert sie einen HLS-Stream?"
        case .stalled:
            return "Der Stream liefert seit einiger Zeit keine Bilddaten mehr."
        case .streamEnded:
            return "Der Live-Stream wurde vom Server beendet."
        case .unauthorized:
            return "Der Server hat den Zugriff abgelehnt (HTTP 401/403). Prüfe das Home-Assistant-Token in den Einstellungen bzw. die Stream-URL."
        case .missingStreamURL:
            return "Verbinde Home Assistant in den Einstellungen oder hinterlege dort bzw. in Cameras.json eine Stream-URL."
        case .invalidStreamURL:
            return "Es werden nur http:// und https:// URLs auf einen HLS-Stream (.m3u8) unterstützt."
        case .insecureConnectionBlocked:
            return "Die unverschlüsselte Verbindung wurde von App Transport Security blockiert. Verwende https:// oder eine lokale Adresse."
        }
    }
}

extension StreamError: LocalizedError {
    var errorDescription: String? { title }
    var recoverySuggestion: String? { message }
}

// MARK: - Klassifizierung

extension StreamError {
    /// Bildet einen beliebigen Fehler (URLSession, AVFoundation, CoreMedia) auf einen
    /// `StreamError` ab. AVFoundation verpackt Netzwerkfehler häufig als
    /// `NSUnderlyingErrorKey`, daher wird die Kette der zugrunde liegenden Fehler durchsucht.
    init(classifying error: any Error) {
        if let streamError = error as? StreamError {
            self = streamError
            return
        }
        if let homeAssistantError = error as? HomeAssistantError {
            self = homeAssistantError.streamError
            return
        }
        if let urlErrorCode = Self.firstURLErrorCode(in: error as NSError) {
            self = Self.classify(urlErrorCode)
            return
        }
        self = .streamUnavailable(statusCode: nil)
    }

    private static func firstURLErrorCode(in error: NSError) -> URLError.Code? {
        var current: NSError? = error
        var depth = 0
        while let candidate = current, depth < 8 {
            if candidate.domain == NSURLErrorDomain {
                return URLError.Code(rawValue: candidate.code)
            }
            current = candidate.userInfo[NSUnderlyingErrorKey] as? NSError
            depth += 1
        }
        return nil
    }

    private static func classify(_ code: URLError.Code) -> StreamError {
        switch code {
        case .badURL, .unsupportedURL:
            return .invalidStreamURL
        case .appTransportSecurityRequiresSecureConnection:
            return .insecureConnectionBlocked
        case .userAuthenticationRequired, .userCancelledAuthentication, .noPermissionsToReadFile:
            return .unauthorized
        case .notConnectedToInternet, .cannotFindHost, .cannotConnectToHost,
             .networkConnectionLost, .dnsLookupFailed, .timedOut,
             .internationalRoamingOff, .dataNotAllowed, .callIsActive,
             .secureConnectionFailed, .serverCertificateUntrusted,
             .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid, .clientCertificateRejected,
             .clientCertificateRequired, .cannotLoadFromNetwork:
            return .homeAssistantUnreachable
        default:
            return .streamUnavailable(statusCode: nil)
        }
    }
}
