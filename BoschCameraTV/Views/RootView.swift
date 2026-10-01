import SwiftUI

/// Navigationsziele der App.
enum Route: Hashable {
    case camera(Camera)
    case settings
}

/// Wurzel der App: Kameraauswahl in einem `NavigationStack`.
/// Die Menü-/Zurück-Taste der Siri Remote führt aus jedem Ziel zurück zur Auswahl.
struct RootView: View {
    let dependencies: AppDependencies

    @State private var path: [Route] = []
    @State private var listViewModel: CameraListViewModel
    @State private var hasHandledLaunch = false

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        _listViewModel = State(initialValue: CameraListViewModel(
            cameraService: dependencies.cameraService,
            settings: dependencies.settings
        ))
    }

    var body: some View {
        NavigationStack(path: $path) {
            CameraListView(
                viewModel: listViewModel,
                onSelect: openCamera,
                onOpenSettings: { path.append(.settings) }
            )
            .navigationDestination(for: Route.self) { route in
                destination(for: route)
            }
        }
        .task { await handleLaunch() }
        .onChange(of: path) { oldPath, newPath in
            // Nach dem Verlassen der Einstellungen Kameras neu laden (geänderte URLs).
            if oldPath.contains(.settings), !newPath.contains(.settings) {
                Task { await listViewModel.load() }
            }
        }
    }

    @ViewBuilder
    private func destination(for route: Route) -> some View {
        switch route {
        case .camera(let camera):
            CameraPlayerView(viewModel: PlayerViewModel(
                camera: camera,
                streamPlayer: dependencies.streamPlayer
            ))
        case .settings:
            SettingsView(viewModel: SettingsViewModel(
                cameraService: dependencies.cameraService,
                settings: dependencies.settings,
                homeAssistant: dependencies.homeAssistant,
                api: dependencies.homeAssistantAPI,
                localConfigurationSummary: dependencies.localConfigurationSummary
            ))
        }
    }

    private func openCamera(_ camera: Camera) {
        listViewModel.select(camera)
        path.append(.camera(camera))
    }

    /// Lädt die (lokalen) Kameras und öffnet – falls gewünscht – direkt die zuletzt
    /// genutzte Kamera, damit beim Start möglichst schnell ein Bild erscheint.
    private func handleLaunch() async {
        guard !hasHandledLaunch else { return }
        hasHandledLaunch = true
        await listViewModel.load()
        guard let camera = listViewModel.cameraForAutoOpen() else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            path = [.camera(camera)]
        }
    }
}
