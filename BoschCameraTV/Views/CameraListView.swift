import SwiftUI

/// Home-Screen „Meine Kameras“ – für die Bedienung mit der Siri Remote aus 3 m Entfernung.
struct CameraListView: View {
    let viewModel: CameraListViewModel
    let streams: any StreamProviding
    let onSelect: (Camera) -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        if case .loaded(let cameras) = viewModel.state, !cameras.isEmpty {
            // Normalfall: randloser Live-Monitor ohne Kopfzeile.
            LiveCameraGrid(
                cameras: cameras,
                streams: streams,
                preferredCameraID: viewModel.preferredCameraID,
                onSelect: onSelect,
                onOpenSettings: onOpenSettings
            )
        } else {
            VStack(alignment: .leading, spacing: 48) {
                header
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(BackgroundGradient().ignoresSafeArea())
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 40) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Meine Kameras")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("Live-Bild über Home Assistant")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onOpenSettings) {
                Label("Einstellungen", systemImage: "gearshape")
            }
        }
        // Eigene Fokus-Sektion: „nach oben“ erreicht den Button von jeder Kachel aus.
        .focusSection()
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView("Kameras werden geladen…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("Kameras nicht verfügbar", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Erneut laden") {
                    Task { await viewModel.load() }
                }
                Button("Einstellungen", action: onOpenSettings)
            }
        case .loaded(let cameras) where cameras.isEmpty:
            ContentUnavailableView {
                Label("Keine Kameras konfiguriert", systemImage: "video.slash")
            } description: {
                Text("Verbinde Home Assistant in den Einstellungen oder lege eine Datei „Cameras.json“ an (siehe README).")
            }
        case .loaded:
            EmptyView()
        }
    }
}

/// Dezenter, dunkler Hintergrund passend zum Dark Mode.
private struct BackgroundGradient: View {
    var body: some View {
        LinearGradient(
            colors: [Color(white: 0.11), Color(white: 0.03)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

#Preview {
    let settings = SettingsStore(defaults: UserDefaults(suiteName: "preview") ?? .standard)
    let provider = LocalCameraProvider(data: Data(PreviewData.camerasJSON.utf8))
    let viewModel = CameraListViewModel(
        cameraService: CameraService(provider: provider, settings: settings),
        settings: settings
    )
    return CameraListView(
        viewModel: viewModel,
        streams: StreamPlayerPool { StreamPlayer() },
        onSelect: { _ in },
        onOpenSettings: {}
    )
        .task { await viewModel.load() }
}
