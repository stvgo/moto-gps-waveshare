import Combine
import Foundation
import MapKit
import MotoNavigationCore
import SwiftUI

struct SurroundingMapStatusRow: View {
    @ObservedObject var store: SurroundingMapStore

    var body: some View {
        LabeledContent {
            Text(store.statusText).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
        } label: { Label("Mapa de entorno", systemImage: "map") }
    }
}

struct MapCity: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let detail: String
    let boundsWGS84: [Double]

    enum CodingKeys: String, CodingKey {
        case id, name, detail
        case boundsWGS84 = "bounds_wgs84"
    }
}

@MainActor
final class MapCitySearch: ObservableObject {
    @Published var query = ""
    @Published private(set) var cities: [MapCity] = []
    @Published private(set) var isSearching = false
    @Published private(set) var errorMessage: String?
    private let baseURL: URL
    private var task: Task<Void, Never>?
    private var generation = 0

    init(baseURL: URL) { self.baseURL = baseURL }
    deinit { task?.cancel() }

    func search() {
        task?.cancel()
        generation += 1
        let current = generation
        cities = []
        errorMessage = nil
        let keywords = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2 ... 80).contains(keywords.count) else { isSearching = false; return }
        isSearching = true
        var components = URLComponents(url: baseURL.appendingPathComponent("v1/map/cities"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "keywords", value: keywords)]
        let url = components.url!
        task = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(350))
                var request = URLRequest(url: url)
                request.timeoutInterval = 20
                let (data, response) = try await URLSession.shared.data(for: request)
                try Task.checkCancellation()
                guard let response = response as? HTTPURLResponse,
                      response.statusCode == 200, data.count <= 1_048_576
                else { throw URLError(.badServerResponse) }
                struct Reply: Decodable { let cities: [MapCity] }
                let reply = try JSONDecoder().decode(Reply.self, from: data)
                let valid = reply.cities.prefix(30).filter { city in
                    let b = city.boundsWGS84
                    return b.count == 4 && b.allSatisfy(\.isFinite) && b[0] < b[2] && b[1] < b[3] &&
                        b[0] >= -180 && b[2] <= 180 && b[1] >= -85 && b[3] <= 85
                }
                guard let self, self.generation == current else { return }
                self.cities = Array(valid)
                self.isSearching = false
            } catch {
                guard !Task.isCancelled, let self, self.generation == current else { return }
                self.isSearching = false
                self.errorMessage = "No se pudieron buscar ciudades. Verifica tu conexión."
            }
        }
    }
}

struct MapDownloadsView: View {
    @ObservedObject var store: SurroundingMapStore
    let gatewayBaseURL: URL
    let route: [GCJ02Point]
    let destinationName: String?
    @Environment(\.dismiss) private var dismiss
    @State private var planningRoute = false
    @State private var planningError: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Cargar mapa de entorno automáticamente")
                            Text(store.statusText).font(.subheadline).foregroundStyle(.secondary)
                        }
                    } icon: { Image(systemName: "network").foregroundStyle(.blue) }
                } footer: {
                    Text("Carga carreteras y edificios alrededor del vehículo mientras ruedas. Sin conexión usa los mapas descargados.")
                }
                Section {
                    NavigationLink {
                        MapCitySearchView(store: store, baseURL: gatewayBaseURL)
                    } label: {
                        Label("Descargar mapa de ciudad", systemImage: "building.2.crop.circle")
                    }
                    .accessibilityIdentifier("map-download-city")
                    if route.count >= 2 {
                        Button(action: downloadRoute) {
                            Label {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(planningRoute ? "Calculando área de descarga…" : "Descargar mapa de esta ruta")
                                    Text(destinationName ?? "Ruta seleccionada")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                            } icon: { Image(systemName: "arrow.triangle.turn.up.right.diamond") }
                        }
                        .disabled(store.isDownloading || planningRoute)
                        .accessibilityIdentifier("map-download-route")
                    }
                } footer: {
                    Text("Guarda mapas a lo largo de tu recorrido para navegar sin datos móviles.")
                }
                downloadStatus(store)
                if let planningError {
                    Section { Text(planningError).foregroundStyle(.secondary) }
                }
                Section("Guardados") {
                    if store.packs.isEmpty {
                        Text("No hay mapas descargados")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.packs) { pack in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(pack.name).font(.headline)
                                Spacer()
                                Image(systemName: pack.isComplete ? "checkmark.circle.fill" : "pause.circle")
                                    .foregroundStyle(pack.isComplete ? Color.green : Color.secondary)
                            }
                            Text(pack.detail).font(.subheadline).foregroundStyle(.secondary)
                            Text("\(ByteCountFormatter.string(fromByteCount: pack.byteCount, countStyle: .file)) · \(pack.isComplete ? "Descargado" : "Incompleto")")
                                .font(.footnote).foregroundStyle(.secondary)
                            if !pack.isComplete && !store.isDownloading {
                                Button("Reanudar") { store.resume(pack) }.buttonStyle(.borderless)
                            }
                        }
                        .padding(.vertical, 4)
                        .swipeActions {
                            Button("Eliminar", role: .destructive) { store.delete(pack) }
                                .disabled(store.isDownloading)
                        }
                    }
                }
                Section {
                    Button("Limpiar caché automática") { store.clearTemporaryCache() }
                        .disabled(store.isDownloading)
                } footer: {
                    Text("Conserva los mapas descargados manualmente y libera memoria temporal.")
                }
                Section {
                    Link("© OpenStreetMap contributors", destination: URL(string: "https://www.openstreetmap.org/copyright")!)
                    Link("Protomaps", destination: URL(string: "https://protomaps.com")!)
                } footer: { Text("Datos de vías y edificios provistos por OpenStreetMap.") }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Mapas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }.accessibilityIdentifier("map-downloads-done")
                }
            }
            .accessibilityIdentifier("map-downloads-sheet")
        }
    }

    private func downloadRoute() {
        planningRoute = true
        planningError = nil
        let points = route
        Task {
            do {
                let tiles = try await Task.detached(priority: .userInitiated) {
                    try MapTilePlanner.corridorGCJ02(points)
                }.value
                store.download(name: "Hacia \(destinationName ?? "Destino")", detail: "Ruta seleccionada y 1 km a la redonda", tiles: tiles)
            } catch { planningError = error.localizedDescription }
            planningRoute = false
        }
    }
}

private struct MapCitySearchView: View {
    @ObservedObject var store: SurroundingMapStore
    @StateObject private var search: MapCitySearch

    init(store: SurroundingMapStore, baseURL: URL) {
        self.store = store
        _search = StateObject(wrappedValue: MapCitySearch(baseURL: baseURL))
    }

    var body: some View {
        List {
            if search.isSearching {
                HStack { ProgressView(); Text("Buscando ciudad…").foregroundStyle(.secondary) }
            } else if let message = search.errorMessage {
                Text(message)
                Button("Reintentar") { search.search() }
            } else if search.cities.isEmpty {
                ContentUnavailableView(
                    search.query.count >= 2 ? "No se encontró la ciudad" : "Buscar ciudades",
                    systemImage: "building.2",
                    description: Text("Escribe el nombre de la ciudad o municipio.")
                )
            } else {
                ForEach(search.cities) { city in
                    NavigationLink {
                        MapCityDownloadView(store: store, city: city)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(city.name)
                            Text(city.detail).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("map-city-result-\(city.id)")
                }
            }
        }
        .navigationTitle("Descargar Ciudad")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search.query, prompt: "Buscar ciudad o municipio")
        .onChange(of: search.query) { _, _ in search.search() }
    }
}

private struct MapCityDownloadView: View {
    @ObservedObject var store: SurroundingMapStore
    let city: MapCity
    @State private var tiles: [MapTileID] = []
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Map(initialPosition: .region(region)) {
                    MapPolygon(coordinates: corners)
                        .foregroundStyle(.blue.opacity(0.1))
                        .stroke(.blue, lineWidth: 2)
                }
                .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                .frame(height: 260)
                .listRowInsets(EdgeInsets())
                .accessibilityLabel("Área de descarga de \(city.name)")
                LabeledContent("Zona", value: city.detail)
            } footer: {
                Text("Los mapas de esta zona se guardarán para usarse sin conexión.")
            }
            Section {
                if let errorMessage { Text(errorMessage).foregroundStyle(.secondary) }
                Button("Descargar Mapa") {
                    store.download(name: city.name, detail: city.detail, tiles: tiles)
                }
                .disabled(tiles.isEmpty || store.isDownloading)
                .accessibilityIdentifier("map-city-start-download")
            } footer: {
                Text("Recomendado descargar mediante Wi-Fi.")
            }
            downloadStatus(store)
        }
        .navigationTitle(city.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do { tiles = try MapTilePlanner.boundsWGS84(city.boundsWGS84) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private var region: MKCoordinateRegion {
        let b = city.boundsWGS84
        return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: (b[1] + b[3]) / 2, longitude: (b[0] + b[2]) / 2),
            span: MKCoordinateSpan(latitudeDelta: (b[3] - b[1]) * 1.15, longitudeDelta: (b[2] - b[0]) * 1.15))
    }

    private var corners: [CLLocationCoordinate2D] {
        let b = city.boundsWGS84
        return [(b[1], b[0]), (b[1], b[2]), (b[3], b[2]), (b[3], b[0])].map {
            CLLocationCoordinate2D(latitude: $0.0, longitude: $0.1)
        }
    }
}

@MainActor @ViewBuilder
private func downloadStatus(_ store: SurroundingMapStore) -> some View {
    if store.isDownloading {
        Section {
            ProgressView(value: store.downloadProgress)
                .accessibilityLabel("Progreso de descarga")
            Text(store.downloadMessage ?? "Descargando…").font(.subheadline).foregroundStyle(.secondary)
            Button("Pausar descarga") { store.cancelDownload() }
        }
    } else if let message = store.downloadMessage {
        Section { Text(message).font(.subheadline).foregroundStyle(.secondary) }
    }
}
