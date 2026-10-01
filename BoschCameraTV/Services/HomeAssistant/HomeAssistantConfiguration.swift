import Foundation

/// Verbindungsdaten für Home Assistant. Die Server-URL liegt in `UserDefaults`,
/// das Token ausschließlich in der Keychain.
struct HomeAssistantConfiguration: Equatable, Sendable {
    let serverURL: URL
    let accessToken: String

    var statesURL: URL {
        serverURL.appending(path: "api/states")
    }

    var webSocketURL: URL? {
        guard var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = serverURL.scheme?.lowercased() == "https" ? "wss" : "ws"
        components.path = "/api/websocket"
        return components.url
    }

    /// Macht aus einem von Home Assistant gelieferten Pfad (z. B. `/api/hls/…`) eine volle URL.
    func absoluteURL(forPath path: String) -> URL? {
        URL(string: path, relativeTo: serverURL)?.absoluteURL
    }

    /// Normalisiert eine Benutzereingabe auf Schema, Host und Port,
    /// z. B. `192.168.1.10:8123` → `http://192.168.1.10:8123`.
    static func serverURL(from text: String) -> URL? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.contains("://") {
            trimmed = "http://" + trimmed
        }
        guard let url = URL(string: trimmed), url.isSupportedStreamURL,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.path = ""
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil
        return components.url
    }
}

/// Fehler der Home-Assistant-Anbindung.
enum HomeAssistantError: Error, Equatable, LocalizedError {
    case notConfigured
    case invalidServerURL
    case unauthorized
    case unreachable
    case insecureConnectionBlocked
    case httpStatus(Int)
    case invalidResponse
    case commandFailed(String)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Home Assistant ist nicht eingerichtet. Trage Server-Adresse und Token in den Einstellungen ein."
        case .invalidServerURL:
            return "Die Home-Assistant-Adresse ist ungültig."
        case .unauthorized:
            return "Home Assistant hat das Token abgelehnt. Prüfe das langlebige Zugangs-Token in den Einstellungen."
        case .unreachable:
            return "Keine Verbindung zu Home Assistant. Prüfe die Server-Adresse und ob das Apple TV im selben Netzwerk ist."
        case .insecureConnectionBlocked:
            return "Die unverschlüsselte Verbindung wurde blockiert. Verwende die IP-Adresse (z. B. http://192.168.1.10:8123) oder https://."
        case .httpStatus(let code):
            return "Home Assistant antwortet mit HTTP \(code)."
        case .invalidResponse:
            return "Unerwartete Antwort von Home Assistant."
        case .commandFailed(let message):
            return "Home Assistant konnte den Stream nicht starten: \(message)"
        case .timedOut:
            return "Home Assistant hat den Stream nicht rechtzeitig bereitgestellt."
        }
    }

    /// Abbildung auf die Fehlerarten des Players (Retry-Verhalten, Texte).
    var streamError: StreamError {
        switch self {
        case .notConfigured:
            return .missingStreamURL
        case .invalidServerURL:
            return .invalidStreamURL
        case .unauthorized:
            return .unauthorized
        case .unreachable:
            return .homeAssistantUnreachable
        case .insecureConnectionBlocked:
            return .insecureConnectionBlocked
        case .httpStatus(let code):
            return code == 401 || code == 403 ? .unauthorized : .streamUnavailable(statusCode: code)
        case .invalidResponse, .commandFailed, .timedOut:
            return .streamUnavailable(statusCode: nil)
        }
    }

    /// Bildet Transportfehler (URLSession) auf verständliche Fehler ab.
    static func mapping(_ error: any Error) -> any Error {
        if error is HomeAssistantError || error is CancellationError { return error }
        if let urlError = error as? URLError, urlError.code == .cancelled { return error }
        switch StreamError(classifying: error) {
        case .homeAssistantUnreachable:
            return HomeAssistantError.unreachable
        case .insecureConnectionBlocked:
            return HomeAssistantError.insecureConnectionBlocked
        case .invalidStreamURL:
            return HomeAssistantError.invalidServerURL
        default:
            return error
        }
    }
}

/// Speicher für das Home-Assistant-Token (in der App: Keychain).
protocol HomeAssistantTokenStoring: Sendable {
    func accessToken() throws -> String?
    func setAccessToken(_ token: String) throws
    func removeAccessToken() throws
}

/// Liefert die aktuelle Konfiguration – `nil`, solange Server oder Token fehlen.
/// Wird bei jedem Zugriff neu gelesen, damit Änderungen in den Einstellungen sofort gelten.
struct HomeAssistantConfigurationProvider: Sendable {
    let settings: SettingsStore
    let tokens: any HomeAssistantTokenStoring

    func current() -> HomeAssistantConfiguration? {
        guard let serverURL = settings.homeAssistantServerURL,
              let token = try? tokens.accessToken(), !token.isEmpty else { return nil }
        return HomeAssistantConfiguration(serverURL: serverURL, accessToken: token)
    }

    var hasStoredToken: Bool {
        guard let token = try? tokens.accessToken() else { return false }
        return !token.isEmpty
    }
}
