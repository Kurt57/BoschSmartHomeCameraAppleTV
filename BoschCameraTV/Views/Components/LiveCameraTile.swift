import SwiftUI

/// Randlose Live-Kachel einer Kamera für die Startseite (stumm, Bild füllt die Fläche).
struct LiveCameraTile: View {
    @State private var viewModel: PlayerViewModel
    private let action: () -> Void

    init(camera: Camera, streams: any StreamProviding, action: @escaping () -> Void) {
        _viewModel = State(initialValue: PlayerViewModel(camera: camera, streams: streams, playsAudio: false))
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                Color.black
                VideoSurfaceView(player: viewModel.player, videoGravity: .resizeAspectFill)
                    .allowsHitTesting(false)

                if let status = viewModel.compactStatus {
                    statusBadge(text: status.text, systemImage: status.systemImage)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                nameLabel
                    .padding(24)
            }
            .clipped()
        }
        .buttonStyle(LiveTileButtonStyle())
        .accessibilityLabel(viewModel.camera.name)
        .accessibilityHint("Öffnet das Livebild im Vollbild")
        .onAppear { viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
    }

    private var nameLabel: some View {
        HStack(spacing: 10) {
            if viewModel.isLive {
                Circle()
                    .fill(.red)
                    .frame(width: 12, height: 12)
            }
            Text(viewModel.camera.name)
                .font(.callout)
                .fontWeight(.semibold)
                .lineLimit(1)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(.black.opacity(0.5), in: Capsule())
    }

    private func statusBadge(text: String, systemImage: String?) -> some View {
        VStack(spacing: 14) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 44, weight: .semibold))
            } else {
                ProgressView()
            }
            Text(text)
                .font(.callout)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

/// Fokus als weißer Rahmen statt Vergrößerung – die Kacheln bleiben lückenlos.
struct LiveTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        LiveTileChrome(label: configuration.label, isPressed: configuration.isPressed)
    }
}

private struct LiveTileChrome<Label: View>: View {
    let label: Label
    let isPressed: Bool
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        label
            .overlay {
                Rectangle()
                    .strokeBorder(isFocused ? Color.white : Color.clear, lineWidth: 8)
            }
            .opacity(isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}
