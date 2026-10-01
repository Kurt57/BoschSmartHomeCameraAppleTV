import SwiftUI

/// Einstellungen: Start-Verhalten und Stream-URLs je Kamera (lokal in UserDefaults).
///
/// Texteingaben öffnen die tvOS-Tastatur; alternativ kann auch die Tastatur eines
/// iPhones im selben Netzwerk verwendet werden.
struct SettingsView: View {
    @State private var viewModel: SettingsViewModel

    init(viewModel: SettingsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Form {
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
                Text("Leer lassen, um die URL aus der Konfigurationsdatei zu verwenden. Eingaben werden nur lokal auf diesem Apple TV gespeichert.")
            }

            Section {
                Button("Eigene Stream-URLs zurücksetzen", role: .destructive) {
                    viewModel.resetOverrides()
                }
                .disabled(!viewModel.hasOverrides)
            }

            Section {
                LabeledContent("Konfiguration", value: viewModel.configurationSummary)
                LabeledContent("Version", value: Self.appVersion)
            } header: {
                Text("Info")
            }
        }
        .navigationTitle("Einstellungen")
        .task { await viewModel.load() }
    }

    private func streamURLRow(for entry: SettingsViewModel.Entry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(entry.isEnabled ? entry.name : "\(entry.name) (deaktiviert)")
                .font(.headline)
            TextField(entry.configuredURL?.absoluteString ?? "http://homeassistant.local:8123/…", text: overrideBinding(for: entry.id))
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
