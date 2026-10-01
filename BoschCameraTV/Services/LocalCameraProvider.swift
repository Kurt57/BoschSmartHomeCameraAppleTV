import Foundation

/// Fehler beim Laden der lokalen Kamera-Konfiguration.
enum CameraConfigurationError: Error, Equatable, LocalizedError {
    case fileNotFound
    case unreadable(String)
    case invalidFormat(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Keine Kamera-Konfiguration gefunden (Cameras.json)."
        case .unreadable(let detail):
            return "Die Kamera-Konfiguration konnte nicht gelesen werden: \(detail)"
        case .invalidFormat(let detail):
            return "Die Kamera-Konfiguration ist ungültig: \(detail)"
        }
    }
}

/// Lädt Kameras aus einer lokalen JSON-Datei.
///
/// Reihenfolge im App-Bundle:
/// 1. `Cameras.json` – persönliche Konfiguration, wird **nicht** eingecheckt (.gitignore)
/// 2. `Cameras.example.json` – Beispiel mit Platzhalter-URLs
///
/// Format: ein JSON-Array aus Objekten mit `id`, `name`, `streamURL` und optional `enabled`.
struct LocalCameraProvider: CameraProvider {
    static let userConfigurationName = "Cameras"
    static let exampleConfigurationName = "Cameras.example"

    private enum Source: Sendable {
        case file(URL?)
        case data(Data)
    }

    private let source: Source

    /// URL der verwendeten Konfigurationsdatei (falls dateibasiert).
    var configurationURL: URL? {
        if case .file(let url) = source { return url }
        return nil
    }

    /// `true`, wenn nur die Beispielkonfiguration gefunden wurde.
    var isUsingExampleConfiguration: Bool {
        configurationURL?.lastPathComponent == "\(Self.exampleConfigurationName).json"
    }

    init(bundle: Bundle = .main) {
        let url = bundle.url(forResource: Self.userConfigurationName, withExtension: "json")
            ?? bundle.url(forResource: Self.exampleConfigurationName, withExtension: "json")
        source = .file(url)
    }

    init(fileURL: URL) {
        source = .file(fileURL)
    }

    /// Für Tests und Previews.
    init(data: Data) {
        source = .data(data)
    }

    func cameras() async throws -> [Camera] {
        let data = try loadData()
        do {
            return try JSONDecoder().decode([Camera].self, from: data)
        } catch let error as DecodingError {
            throw CameraConfigurationError.invalidFormat(Self.describe(error))
        }
    }

    private func loadData() throws -> Data {
        switch source {
        case .data(let data):
            return data
        case .file(.none):
            throw CameraConfigurationError.fileNotFound
        case .file(let url?):
            do {
                return try Data(contentsOf: url)
            } catch {
                throw CameraConfigurationError.unreadable(error.localizedDescription)
            }
        }
    }

    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, let context):
            return "Feld „\(key.stringValue)“ fehlt (\(path(context)))."
        case .typeMismatch(_, let context), .valueNotFound(_, let context):
            return "Unerwarteter Wert bei \(path(context))."
        case .dataCorrupted(let context):
            return context.debugDescription
        @unknown default:
            return String(describing: error)
        }
    }

    private static func path(_ context: DecodingError.Context) -> String {
        let components = context.codingPath.map { key in
            key.intValue.map { index in "[\(index)]" } ?? key.stringValue
        }
        return components.isEmpty ? "Wurzel" : components.joined(separator: ".")
    }
}
