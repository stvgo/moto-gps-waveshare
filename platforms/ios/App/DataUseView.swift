import SwiftUI

/// Available without a connection, so permission and storage information can
/// still be read when the gateway or the accessory is unavailable.
struct DataUseView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Ubicación y Rutas") {
                    Text("Al buscar lugares y calcular rutas, las coordenadas y términos de búsqueda se envían a tu servidor de navegación. La ubicación se usa en segundo plano para actualizar la pantalla de la moto mientras ruedas.")
                    Text("Al finalizar la navegación se detiene el uso de GPS en segundo plano. Puedes cambiar los permisos en Ajustes del iPhone.")
                }
                Section("Bluetooth y Música") {
                    Text("Al conectar la pantalla circular, las indicaciones, velocidad y mapas se sincronizan por BLE. Si autorizas Apple Music, el título de la canción se muestra en la pantalla de la moto y puedes cambiar de canción con sus controles.")
                    Text("La información de música se procesa de forma local y no se comparte con ningún servidor.")
                }
                Section("Almacenamiento Local") {
                    Text("Los destinos recientes y mapas guardados se almacenan localmente en el iPhone. Puedes borrarlos en cualquier momento desde la pantalla principal.")
                }
                Section {
                    Link("Mapbox Privacy Policy", destination: URL(string: "https://www.mapbox.com/legal/privacy")!)
                    Link("Apple Privacy Policy", destination: URL(string: "https://www.apple.com/legal/privacy/")!)
                    Link("OpenStreetMap License", destination: URL(string: "https://www.openstreetmap.org/copyright")!)
                } header: {
                    Text("Servicios de Mapas")
                } footer: {
                    Text("El mapa del celular usa Apple Maps y los datos de rutas provienen de Mapbox / OpenStreetMap.")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Privacidad y Datos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                        .accessibilityIdentifier("privacy-data-done")
                }
            }
        }
    }
}
