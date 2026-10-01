import SwiftUI

/// Kameraname und Live-Status oben links – wird nach wenigen Sekunden ausgeblendet.
struct CameraInfoBar: View {
    let name: String
    let isLive: Bool

    var body: some View {
        HStack(spacing: 20) {
            Text(name)
                .font(.title3)
                .fontWeight(.semibold)
            if isLive {
                HStack(spacing: 10) {
                    Circle()
                        .fill(.red)
                        .frame(width: 14, height: 14)
                    Text("LIVE")
                        .font(.caption)
                        .fontWeight(.bold)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Live")
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

/// Lade- bzw. Reconnect-Anzeige in der Bildmitte.
struct PlayerProgressView: View {
    let title: String
    let detail: String?

    var body: some View {
        VStack(spacing: 24) {
            ProgressView()
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
            if let detail {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 60)
        .padding(.vertical, 44)
        .frame(minWidth: 520)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Dezentes Pausensymbol über dem eingefrorenen Bild.
struct PausedIndicator: View {
    var body: some View {
        Image(systemName: "pause.fill")
            .font(.system(size: 64, weight: .bold))
            .padding(48)
            .background(.ultraThinMaterial, in: Circle())
            .accessibilityLabel("Pausiert")
    }
}

/// Fehlerkarte mit Erklärung und fokussierbaren Aktionen.
struct PlayerFailureView<Actions: View>: View {
    let title: String
    let message: String
    let systemImage: String
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(spacing: 28) {
            Image(systemName: systemImage)
                .font(.system(size: 72, weight: .semibold))
                .foregroundStyle(.yellow)
            Text(title)
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 1000)
            HStack(spacing: 40) {
                actions()
            }
            .padding(.top, 12)
        }
        .padding(64)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 40, style: .continuous))
        .padding(80)
    }
}
