import AVFoundation
import OSLog
import SwiftUI

@main
struct BoschCameraTVApp: App {
    @State private var dependencies = AppDependencies.live()

    init() {
        Self.configureAudioSession()
        Log.app.info("App gestartet")
    }

    var body: some Scene {
        WindowGroup {
            RootView(dependencies: dependencies)
                .preferredColorScheme(.dark)
        }
    }

    /// Wiedergabe-Kategorie, damit der Kameraton (falls vorhanden) wie bei
    /// Video-Apps behandelt wird.
    private static func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        } catch {
            Log.app.error("Audio-Session konnte nicht konfiguriert werden: \(error.localizedDescription, privacy: .public)")
        }
    }
}
