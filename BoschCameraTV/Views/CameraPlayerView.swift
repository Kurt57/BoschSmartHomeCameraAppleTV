import SwiftUI

/// Vollbild-Livebild einer Kamera.
///
/// Siri Remote:
/// - Play/Pause-Taste oder Klick aufs Touchpad: Pause/Fortsetzen (im Fehlerfall: erneut versuchen)
/// - Wischen: Kameraname und Status kurz einblenden
/// - Menü-/Zurück-Taste: zurück zur Kameraauswahl
struct CameraPlayerView: View {
    @State private var viewModel: PlayerViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedTarget: FocusTarget?

    private enum FocusTarget: Hashable {
        case video
        case retry
        case back
    }

    init(viewModel: PlayerViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        let overlay = viewModel.overlay
        ZStack {
            videoLayer(overlay: overlay)
            switch overlay {
            case .failure(let title, let message, let systemImage):
                failureLayer(title: title, message: message, systemImage: systemImage)
            case .none, .progress, .paused:
                EmptyView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: overlay)
        .animation(.easeInOut(duration: 0.3), value: viewModel.isInfoVisible)
        .onPlayPauseCommand { viewModel.togglePlayPause() }
        .defaultFocus($focusedTarget, .video)
        .onAppear {
            viewModel.onAppear()
            focusedTarget = .video
        }
        .onDisappear { viewModel.onDisappear() }
        .onChange(of: viewModel.isShowingFailure) { _, isShowingFailure in
            focusedTarget = isShowingFailure ? .retry : .video
        }
    }

    /// Video plus schlanke Statusanzeigen. Die gesamte Fläche ist das Fokusziel, damit
    /// Play/Pause und Klicks der Siri Remote ankommen.
    private func videoLayer(overlay: PlayerViewModel.Overlay) -> some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            VideoSurfaceView(player: viewModel.player)
                .ignoresSafeArea()
                .accessibilityLabel("Live-Bild \(viewModel.camera.name)")

            statusContent(overlay)

            if viewModel.isInfoVisible || overlay != .none {
                CameraInfoBar(name: viewModel.camera.name, isLive: viewModel.isLive)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .transition(.opacity)
            }
        }
        .focusable(!viewModel.isShowingFailure)
        .focused($focusedTarget, equals: .video)
        .focusEffectDisabled()
        .onTapGesture { viewModel.togglePlayPause() }
        .onMoveCommand { _ in viewModel.showInfoTemporarily() }
    }

    @ViewBuilder
    private func statusContent(_ overlay: PlayerViewModel.Overlay) -> some View {
        switch overlay {
        case .progress(let title, let detail):
            PlayerProgressView(title: title, detail: detail)
                .transition(.opacity)
        case .paused:
            PausedIndicator()
                .transition(.opacity)
        case .none, .failure:
            EmptyView()
        }
    }

    private func failureLayer(title: String, message: String, systemImage: String) -> some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
            PlayerFailureView(title: title, message: message, systemImage: systemImage) {
                Button {
                    viewModel.retry()
                } label: {
                    Label("Erneut versuchen", systemImage: "arrow.clockwise")
                }
                .focused($focusedTarget, equals: .retry)

                Button {
                    dismiss()
                } label: {
                    Label("Zur Kameraauswahl", systemImage: "square.grid.2x2")
                }
                .focused($focusedTarget, equals: .back)
            }
        }
        .focusSection()
        .transition(.opacity)
    }
}
