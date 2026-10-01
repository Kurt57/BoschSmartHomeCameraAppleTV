import SwiftUI

/// Große, fokussierbare Kachel für eine Kamera (10-foot UI, tvOS-Card-Effekt).
struct CameraTile: View {
    let camera: Camera
    let isLastUsed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                preview
                VStack(alignment: .leading, spacing: 6) {
                    Text(camera.name)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.card)
        .accessibilityLabel(camera.name)
        .accessibilityHint("Öffnet das Live-Bild")
    }

    private var preview: some View {
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.24), Color(white: 0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "video.fill")
                .font(.system(size: 76, weight: .regular))
                .foregroundStyle(.white.opacity(0.85))
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .overlay(alignment: .topTrailing) {
            if isLastUsed {
                Text("Zuletzt angesehen")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())
                    .padding(18)
            }
        }
    }

    /// Host der Stream-URL – genug, um falsche Konfigurationen zu erkennen, ohne
    /// Tokens aus dem Pfad anzuzeigen.
    private var subtitle: String {
        guard let url = camera.streamURL, let host = url.host() else {
            return camera.isHomeAssistantEntity ? "Home Assistant · \(camera.id)" : "Keine Stream-URL konfiguriert"
        }
        if let port = url.port {
            return "\(host):\(port)"
        }
        return host
    }
}
