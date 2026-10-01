import Foundation

/// Öffentlicher Zustand des `StreamPlayer`.
///
/// `failed` trägt einen typisierten `StreamError` (statt `any Error`), damit der Zustand
/// `Equatable` und `Sendable` bleibt und die UI die Fehlerart verlässlich darstellen kann.
enum PlayerState: Equatable, Sendable {
    case idle
    case loading
    case playing
    case paused
    case reconnecting
    case failed(StreamError)
}

/// Feinere Unterteilung von `PlayerState.loading` (bzw. eines laufenden Reconnects),
/// damit die UI zwischen „Verbinde…“ und „Stream wird geladen…“ unterscheiden kann.
enum LoadingStage: Equatable, Sendable {
    /// Stream-URL wird ermittelt und der Server (Home Assistant) kontaktiert.
    case connecting
    /// Der Server antwortet, AVPlayer lädt bzw. puffert den Stream.
    case buffering
}
