import SwiftUI

/// Einstellungen: Home-Assistant-Verbindung, Start-Verhalten und Stream-URLs je Kamera.
///
/// Texteingaben öffnen die tvOS-Tastatur; alternativ kann die Tastatur eines iPhones
/// im selben Netzwerk verwendet werden (Mitteilung „Apple TV-Tastatur“).
struct SettingsView: View {
    @State private var viewModel: SettingsViewModel

    init(viewModel: SettingsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Form {
            homeAssistantSection

            Section {
                Toggle("Zuletzt genutzte Kamera beim Start öffnen", isOn: autoOpenBinding)
            } header: {
                Text("Start")
            } footer: {
                Text("Zeigt nach dem Start sofort das Livebild. Mit der Zurück-Taste gelangst du zur Kameraauswahl.")
            }

            Section {
                if let message = viewModel.loadErrorMessage {
                    Text(message)
                        .foregroundStyle(.red)
                }
                ForEach(viewModel.entries) { entry in
                    streamURLRow(for: entry)
                }
            } header: {
                Text("Stream-URLs")
            } footer: {
                Text("Für Home-Assistant-Kameras ermittelt die App die Adresse automatisch. Ein Eintrag hier überschreibt sie; leer lassen für den Standard. Eingaben werden nur lokal auf diesem Apple TV gespeichert.")
            }

            Section {
                Button("Eigene Stream-URLs zurücksetzen", role: .destructive) {
                    viewModel.resetOverrides()
                }
                .disabled(!viewModel.hasOverrides)
            }

            Section {
                LabeledContent("Kameraquelle", value: viewModel.configurationSummary)
                LabeledContent("Version", value: Self.appVersion)
            } header: {
                Text("Info")
            }
        }
        .navigationTitle("Einstellungen")
        .task(id: viewModel.configurationRevision) { await viewModel.load() }
    }

    // MARK: Home Assistant

    private var homeAssistantSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("Server")
                    .font(.headline)
                TextField("http://192.168.1.10:8123", text: serverURLBinding)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if let message = viewModel.serverURLValidationMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(.vertical, 8)

            VStack(alignment: .leading, spacing: 12) {
                Text("Langlebiges Zugangs-Token")
                    .font(.headline)
                SecureField(
                    viewModel.hasStoredToken ? "Gespeichert – zum Ersetzen neu eingeben" : "Token einfügen",
                    text: tokenBinding
                )
                if let message = viewModel.tokenErrorMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(.vertical, 8)

            Button {
                Task { await viewModel.testConnection() }
            } label: {
                Label("Verbindung testen", systemImage: "antenna.radiowaves.left.and.right")
            }
            .disabled(!viewModel.isHomeAssistantConfigured || viewModel.connectionStatus == .testing)

            connectionStatusRow

            if viewModel.isHomeAssistantConfigured || viewModel.hasStoredToken {
                Button("Home Assistant trennen", role: .destructive) {
                    viewModel.disconnectHomeAssistant()
                }
            }
        } header: {
            Text("Home Assistant")
        } footer: {
            Text("Sind Server und Token hinterlegt, zeigt die App alle camera.*-Entitäten und holt vor jedem Verbindungsaufbau eine frische Stream-Adresse. Das Token erstellst du in Home Assistant unter Profil → Sicherheit; es wird nur in der Keychain gespeichert.")
        }
    }

    @ViewBuilder
    private var connectionStatusRow: some View {
        switch viewModel.connectionStatus {
        case .unknown:
            EmptyView()
        case .testing:
            HStack(spacing: 16) {
                ProgressView()
                Text("Verbinde…")
            }
        case .connected(let count):
            Label("Verbunden – \(count) Kamera(s) gefunden", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }

    // MARK: Stream-URLs

    private func streamURLRow(for entry: SettingsViewModel.Entry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(entry.isEnabled ? entry.name : "\(entry.name) (deaktiviert)")
                .font(.headline)
            TextField(placeholder(for: entry), text: overrideBinding(for: entry.id))
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if let validationMessage = entry.validationMessage {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 8)
    }

    private func placeholder(for entry: SettingsViewModel.Entry) -> String {
        if let url = entry.configuredURL {
            return url.absoluteString
        }
        return entry.isHomeAssistantEntity ? "Automatisch über Home Assistant" : "http://homeassistant.local:8123/…"
    }

    // MARK: Bindings

    private var serverURLBinding: Binding<String> {
        Binding(
            get: { viewModel.serverURLText },
            set: { viewModel.updateServerURL($0) }
        )
    }

    /// Das gespeicherte Token wird nie angezeigt; eine Eingabe ersetzt es.
    private var tokenBinding: Binding<String> {
        Binding(
            get: { "" },
            set: { viewModel.saveToken($0) }
        )
    }

    private var autoOpenBinding: Binding<Bool> {
        Binding(
            get: { viewModel.autoOpenLastCamera },
            set: { viewModel.setAutoOpenLastCamera($0) }
        )
    }

    private func overrideBinding(for cameraID: Camera.ID) -> Binding<String> {
        Binding(
            get: { viewModel.entries.first { $0.id == cameraID }?.overrideText ?? "" },
            set: { viewModel.updateOverride($0, for: cameraID) }
        )
    }

    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
