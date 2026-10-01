import Foundation
import OSLog

/// Zentrale Logger der App (Unified Logging).
///
/// In Console.app bzw. im Xcode-Debug-Bereich nach dem Subsystem filtern, z. B.:
/// `subsystem:com.example.BoschCameraTV category:Player`
///
/// Datenschutz: Stream-URLs können Tokens enthalten und werden daher nie öffentlich
/// geloggt – höchstens mit `privacy: .private`.
enum Log {
    static let subsystem = Bundle.main.bundleIdentifier ?? "com.example.BoschCameraTV"

    static let app = Logger(subsystem: subsystem, category: "App")
    static let cameras = Logger(subsystem: subsystem, category: "Cameras")
    static let player = Logger(subsystem: subsystem, category: "Player")
    static let network = Logger(subsystem: subsystem, category: "Network")
    static let settings = Logger(subsystem: subsystem, category: "Settings")
}
