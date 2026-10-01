import Foundation

/// Exponentielles Backoff für automatische Reconnects.
///
/// Verzögerung für Versuch *n* (1-basiert): `initialDelay · multiplier^(n-1)`,
/// gedeckelt auf `maximumDelay` und um ±`jitterFraction` gestreut, damit mehrere
/// Clients nicht im Gleichtakt auf den Server zugreifen.
struct RetryPolicy: Equatable, Sendable {
    var initialDelay: TimeInterval
    var multiplier: Double
    var maximumDelay: TimeInterval
    /// Anzahl automatischer Reconnect-Versuche, bevor der Player in `.failed` wechselt.
    var maximumAttempts: Int
    var jitterFraction: Double

    /// 1 s, 2 s, 4 s, 8 s, 16 s, 30 s, 30 s, 30 s → nach rund zwei Minuten wird aufgegeben.
    static let `default` = RetryPolicy(
        initialDelay: 1,
        multiplier: 2,
        maximumDelay: 30,
        maximumAttempts: 8,
        jitterFraction: 0.2
    )

    func canRetry(afterAttempts attempts: Int) -> Bool {
        attempts < maximumAttempts
    }

    /// - Parameters:
    ///   - attempt: Nummer des anstehenden Versuchs (beginnend bei 1).
    ///   - randomUnit: Zufallswert in `-1...1` für den Jitter (injizierbar für Tests).
    func delay(forAttempt attempt: Int, randomUnit: Double = .random(in: -1...1)) -> TimeInterval {
        let exponent = Double(max(attempt, 1) - 1)
        let exponential = initialDelay * pow(multiplier, exponent)
        let capped = min(exponential, maximumDelay)
        let jittered = capped * (1 + jitterFraction * min(max(randomUnit, -1), 1))
        return min(max(jittered, 0), maximumDelay)
    }
}
