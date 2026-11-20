import MotoNavigationCore
import SwiftUI

struct GatewaySettingsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var message: String?
    @State private var isChecking = false
    @State private var checkTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://tu-servidor.railway.app/", text: $address, axis: .vertical)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("gateway-address-field")
                        .disabled(model.isUpdatingGateway)
                } header: {
                    Text("Dirección del Servidor")
                } footer: {
                    Text("URL raíz HTTPS del backend (ej. https://moto-gps-waveshare-production.up.railway.app/).")
                }
                Section {
                    Button {
                        checkConnection()
                    } label: {
                        HStack {
                            Text("Probar Conexión")
                            if isChecking { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(isChecking || model.isUpdatingGateway || address.isEmpty)
                    .accessibilityIdentifier("gateway-check-button")
                    if let message {
                        Text(message).foregroundStyle(.secondary)
                            .accessibilityIdentifier("gateway-status-message")
                    }
                } footer: {
                    Text("Verifica el estado del servicio y la conexión a Internet.")
                }
                Section {
                    Text("Los cambios surten efecto de inmediato sin reinstalar la app.")
                    Text("Las búsquedas y rutas se calculan a través de este servidor.")
                }
                if model.isNavigationActive {
                    Section { Text("Finaliza la navegación actual antes de cambiar de servidor.") }
                }
            }
            .navigationTitle("Ajustes de Servidor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }.disabled(model.isUpdatingGateway)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        checkTask?.cancel()
                        isChecking = false
                        Task {
                            do {
                                try await model.saveGatewayAddress(address)
                                dismiss()
                            } catch { message = error.localizedDescription }
                        }
                    }
                    .disabled(model.isNavigationActive || model.isUpdatingGateway || address.isEmpty)
                    .accessibilityIdentifier("gateway-save-button")
                }
            }
            .interactiveDismissDisabled(model.isUpdatingGateway)
            .onAppear { address = model.isGatewayConfigured ? model.mapGatewayBaseURL.absoluteString : "" }
            .onChange(of: address) { _, _ in
                checkTask?.cancel()
                isChecking = false
                message = nil
            }
            .onDisappear { checkTask?.cancel() }
        }
    }

    private func checkConnection() {
        checkTask?.cancel()
        message = nil
        let url: URL
        do { url = try GatewayConfiguration.normalizedURL(address) }
        catch { message = error.localizedDescription; return }
        isChecking = true
        checkTask = Task { @MainActor in
            defer { if !Task.isCancelled { isChecking = false } }
            do {
                var request = URLRequest(url: url.appendingPathComponent("healthz"))
                request.timeoutInterval = 10
                request.cachePolicy = .reloadIgnoringLocalCacheData
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                defer { bytes.task.cancel() }
                guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                      response.expectedContentLength <= 65_536 else { throw URLError(.badServerResponse) }
                var data = Data()
                for try await byte in bytes {
                    guard data.count < 65_536 else { throw URLError(.dataLengthExceedsMaximum) }
                    data.append(byte)
                }
                struct Health: Decodable {
                    let status: String
                    let ready_for_live_navigation: Bool
                }
                let health = try JSONDecoder().decode(Health.self, from: data)
                guard health.status == "ok" else { throw URLError(.badServerResponse) }
                try Task.checkCancellation()
                message = health.ready_for_live_navigation
                    ? "Servidor conectado y listo para navegación en vivo."
                    : "Servidor conectado, pero la navegación en vivo no está habilitada."
            } catch {
                guard !Task.isCancelled else { return }
                message = "Error de conexión. Verifica la URL y tu conexión a Internet."
            }
        }
    }
}
