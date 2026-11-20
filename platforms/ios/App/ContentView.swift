import SwiftUI

enum MotoScreen: Hashable {
    case routePreview
    case activeNavigation
}

/// One primary flow: destination → route → ride. Device management is secondary.
struct ContentView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @FocusState private var searchFocused: Bool
    @State private var showsDeviceDetails = false
    @State private var showsMapDownloads = false
    @State private var showsDataUse = false
    @State private var showsGatewaySettings = false

    var body: some View {
        NavigationStack(path: navigationPath) {
            homeScreen
                .navigationDestination(for: MotoScreen.self) { screen in
                    switch screen {
                    case .routePreview: routePreviewScreen
                    case .activeNavigation: activeNavigationScreen
                    }
                }
        }
        .tint(.blue)
        .onChange(of: model.destinationQuery) { _, _ in model.destinationQueryDidChange() }
        .onChange(of: model.selectedPlace) { _, place in
            if place != nil { searchFocused = false }
        }
        .onChange(of: model.isNavigationActive) { _, active in
            if active { searchFocused = false }
        }
        .sheet(isPresented: $showsDeviceDetails) { deviceDetails }
        .sheet(isPresented: $showsMapDownloads) {
            MapDownloadsView(
                store: model.surroundingMap,
                gatewayBaseURL: model.mapGatewayBaseURL,
                route: model.mapDownloadRoute,
                destinationName: model.selectedPlace?.name
            )
        }
        .sheet(isPresented: $showsDataUse) { DataUseView() }
        .sheet(isPresented: $showsGatewaySettings) { GatewaySettingsView(model: model) }
    }

    // Derive the stack from the session instead of synchronizing two mutable
    // paths with onChange. A system Back gesture uses the same cleanup as End.
    private var navigationPath: Binding<[MotoScreen]> {
        Binding(
            get: {
                if model.isNavigationActive { return [.activeNavigation] }
                if model.selectedPlace != nil { return [.routePreview] }
                return []
            },
            set: { path in
                if model.isNavigationActive, !path.contains(.activeNavigation) {
                    model.stopNavigation()
                } else if model.selectedPlace != nil, !path.contains(.routePreview) {
                    model.clearDestination()
                }
            }
        )
    }

    // MARK: - Destination search

    private var homeScreen: some View {
        List {
            if !model.isGatewayConfigured {
                Section {
                    Button { showsGatewaySettings = true } label: {
                        Label("Configurar Servidor", systemImage: "network")
                    }
                    .accessibilityIdentifier("gateway-setup-button")
                } footer: {
                    Text("Configura la dirección de tu servidor para buscar lugares y calcular rutas.")
                }
            }
            Section { searchField }
            if !model.destinationQuery.isEmpty {
                searchResultsSection
            } else {
                if model.recentPlaces.isEmpty {
                    Section {
                        ContentUnavailableView {
                            Label {
                                Text("Seleccionar Destino")
                                    .lineLimit(nil)
                                    .fixedSize(horizontal: false, vertical: true)
                            } icon: { Image(systemName: "map") }
                        } description: {
                            Text("Busca un lugar o dirección y sal a rodar.")
                        }
                        .padding(.vertical, 12)
                    }
                    .listRowBackground(Color.clear)
                } else {
                    recentPlacesSection
                }
                Section {
                    deviceSummaryButton
                    mapDownloadsButton
                    demoButton
                } footer: {
                    Text("Al conectar la pantalla, las indicaciones se sincronizan automáticamente.")
                }
                Section {
                    Button { showsGatewaySettings = true } label: {
                        Label("Ajustes de Servidor", systemImage: "network")
                            .foregroundStyle(Color.primary)
                    }
                    .accessibilityIdentifier("gateway-settings-button")
                    Button { showsDataUse = true } label: {
                        Label("Privacidad y Datos", systemImage: "hand.raised")
                            .foregroundStyle(Color.primary)
                    }
                    .accessibilityIdentifier("privacy-data-button")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("MOTO GPS")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showsGatewaySettings = true } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Ajustes de Servidor")
                    .accessibilityIdentifier("gateway-settings-toolbar")
            }
            ToolbarItem(placement: .topBarTrailing) { deviceToolbarButton }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Listo") { searchFocused = false }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.secondary)
                .accessibilityHidden(true)
            TextField("Buscar lugar o dirección", text: $model.destinationQuery)
                .font(.body)
                .accessibilityIdentifier("destination-search-field")
                .accessibilityLabel("Buscar destino")
                .focused($searchFocused)
                .submitLabel(.search)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit {
                    model.submitDestinationSearch()
                    searchFocused = false
                }
            if !model.destinationQuery.isEmpty {
                Button {
                    model.clearDestination()
                    searchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.secondary)
                        .frame(minWidth: 28, minHeight: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Borrar búsqueda")
            }
        }
        .frame(minHeight: 44)
    }

    private var searchResultsSection: some View {
        Section {
            if model.isSearchingPlaces {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Buscando…").foregroundStyle(Color.secondary)
                }
                .frame(minHeight: 56)
                .accessibilityElement(children: .combine)
            } else if !model.placeResults.isEmpty {
                ForEach(Array(model.placeResults.enumerated()), id: \.offset) { index, place in
                    Button { select(place) } label: {
                        placeRow(place, symbol: "mappin.circle.fill")
                    }
                    .accessibilityIdentifier("place-result-\(index)")
                }
            } else {
                ContentUnavailableView {
                    Label {
                        Text(model.placeSearchFailure == nil ? "Escribe un lugar" : "Sin resultados")
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: { Image(systemName: "magnifyingglass") }
                } description: {
                    Text(model.placeSearchFailure ?? "Ingresa el nombre de un lugar o dirección.")
                } actions: {
                    if model.placeSearchFailure != nil {
                        Button("Reintentar búsqueda", action: model.submitDestinationSearch)
                    }
                }
            }
        } header: {
            Text("Resultados")
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                Text(model.searchScopeText)
                if model.searchLocationStatus == .permissionDenied {
                    Button("Ir a Ajustes para activar ubicación", action: openSystemSettings)
                }
            }
        }
    }

    private var recentPlacesSection: some View {
        Section {
            ForEach(Array(model.recentPlaces.enumerated()), id: \.offset) { index, place in
                Button { select(place) } label: { placeRow(place, symbol: "clock") }
                    .accessibilityIdentifier("recent-place-\(index)")
            }
        } header: {
            HStack {
                Text("Búsquedas recientes")
                Spacer()
                Button("Borrar", action: model.clearRecentPlaces)
                    .textCase(nil)
                    .accessibilityLabel("Borrar búsquedas recientes")
            }
        }
    }

    private func placeRow(_ place: PlaceSearchResult, symbol: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(symbol == "clock" ? Color.secondary : .blue)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(place.name)
                    .font(.body)
                    .foregroundStyle(Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(placeSubtitle(place))
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(uiColor: .tertiaryLabel))
                .accessibilityHidden(true)
        }
        .padding(.vertical, 7)
        .frame(minHeight: 48)
        .contentShape(Rectangle())
    }

    private func select(_ place: PlaceSearchResult) {
        searchFocused = false
        model.selectPlace(place)
    }

    private var demoButton: some View {
        Button {
            searchFocused = false
            model.startDemoNavigation()
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Modo Simulación / Demo").foregroundStyle(Color.primary)
                    Text("Probar animación de ruta y pantalla")
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                }
            } icon: {
                Image(systemName: "play.circle").foregroundStyle(.blue)
            }
            .padding(.vertical, 5)
        }
        .accessibilityIdentifier("demo-navigation-button")
    }

    // MARK: - Route selection

    private var mapDownloadsButton: some View {
        Button { showsMapDownloads = true } label: {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mapas y Descarga Offline").foregroundStyle(Color.primary)
                    Text("Descargar mapas de la ciudad o a lo largo de tu ruta")
                        .font(.subheadline).foregroundStyle(Color.secondary)
                }
            } icon: { Image(systemName: "map").foregroundStyle(.blue) }
            .padding(.vertical, 5)
        }
        .accessibilityIdentifier("map-downloads-button")
    }

    private var routePreviewScreen: some View {
        List {
            if let place = model.selectedPlace {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(place.name).font(.headline)
                            Text(placeSubtitle(place))
                                .font(.subheadline)
                                .foregroundStyle(Color.secondary)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "mappin.circle.fill").foregroundStyle(.red)
                    }
                    .padding(.vertical, 5)
                } header: {
                    Label("Desde mi ubicación", systemImage: "location.fill").textCase(nil)
                }

                if model.isPlanningRoutePreview {
                    Section {
                        HStack(spacing: 14) {
                            ProgressView()
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Calculando ruta")
                                Text("Obteniendo ubicación y tráfico…")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.secondary)
                            }
                        }
                        .padding(.vertical, 12)
                        .accessibilityIdentifier("route-preview-loading")
                    }
                } else if model.hasRoutePreview {
                    Section {
                        RouteOverviewMap(
                            candidates: model.routePreviewCandidates,
                            selectedID: model.selectedRoutePreviewID,
                            origin: model.routePreviewOrigin,
                            destination: place.location
                        )
                        .frame(height: dynamicTypeSize.isAccessibilitySize ? 220 : 270)
                        .listRowInsets(EdgeInsets())
                        .accessibilityIdentifier("route-preview-map")
                        .accessibilityLabel("Ruta hacia \(place.name)")
                    }
                    Section {
                        ForEach(model.routePreviewCandidates) { candidate in routeOptionRow(candidate) }
                    } header: {
                        Text("Seleccionar Ruta")
                    } footer: {
                        Text("Ruta calculada con tráfico en tiempo real")
                    }
                    Section { mapDownloadsButton }
                } else if let failure = model.routePreviewFailure {
                    Section {
                        ContentUnavailableView {
                            Label {
                                Text("No se pudo calcular la ruta")
                                    .lineLimit(nil)
                                    .fixedSize(horizontal: false, vertical: true)
                            } icon: { Image(systemName: "exclamationmark.triangle") }
                        } description: {
                            Text(failure)
                        } actions: {
                            if model.searchLocationStatus == .permissionDenied {
                                Button("Ir a Ajustes", action: openSystemSettings)
                            }
                        }
                    }
                }
                if let failure = model.navigationFailure {
                    Section { failureMessage(failure) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Ruta")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Cambiar") {
                    model.clearDestination()
                    searchFocused = true
                }
                .accessibilityLabel("Cambiar destino")
                .accessibilityIdentifier("destination-change-button")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { navigationActionBar }
    }

    private func routeOptionRow(_ candidate: RoutePreviewCandidate) -> some View {
        let selected = candidate.id == model.selectedRoutePreviewID
        return Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                model.selectRoutePreview(candidate.id)
            }
        } label: {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(candidate.title)
                        .font(.subheadline)
                        .foregroundStyle(selected ? Color.blue : .secondary)
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            routeDuration(candidate)
                            routeDistance(candidate)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            routeDuration(candidate)
                            routeDistance(candidate)
                        }
                    }
                    Label(candidate.trafficSummary, systemImage: "car.side")
                        .font(.subheadline)
                        .foregroundStyle(trafficTint(candidate))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(selected ? Color.blue : Color(uiColor: .tertiaryLabel))
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("route-option-\(candidate.ordinal)")
        .accessibilityLabel("\(candidate.title)，\(candidate.durationText)，\(candidate.distanceText)，\(candidate.trafficSummary)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func routeDuration(_ candidate: RoutePreviewCandidate) -> some View {
        Text(candidate.durationText)
            .font(.title2.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(Color.primary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func routeDistance(_ candidate: RoutePreviewCandidate) -> some View {
        Text(candidate.distanceText)
            .font(.subheadline)
            .monospacedDigit()
            .foregroundStyle(Color.secondary)
    }

    // MARK: - Ride in progress

    private var activeNavigationScreen: some View {
        List {
            Section {
                VStack(spacing: 14) {
                    Image(systemName: navigationSymbol)
                        .font(.system(size: 36, weight: .medium))
                        .foregroundStyle(model.navigationFailure == nil ? Color.blue : .orange)
                        .frame(width: 76, height: 76)
                        .background(Color.blue.opacity(0.08), in: Circle())
                        .accessibilityHidden(true)
                    Text(navigationTitle)
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                    Text(navigationDetail)
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            }
            .listRowBackground(Color.clear)
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(model.isDemoActive ? "Destino de Demo" : "Destino")
                            .font(.subheadline)
                            .foregroundStyle(Color.secondary)
                        Text(model.activeDestinationName).font(.headline)
                    }
                } icon: {
                    Image(systemName: "flag.checkered").foregroundStyle(.blue)
                }
                .padding(.vertical, 6)
                if dynamicTypeSize.isAccessibilitySize {
                    rideMetric("Tiempo rest.", value: remainingDuration)
                    rideMetric("Distancia", value: remainingDistance)
                } else {
                    HStack(spacing: 24) {
                        rideMetric("Tiempo rest.", value: remainingDuration)
                        rideMetric("Distancia", value: remainingDistance)
                    }
                }
            }
            Section("Estado de Navegación") {
                deviceSummaryButton
                statusRow("GPS del Celular", symbol: "location", value: locationStatus,
                          color: model.navigation.hasUsableFix ? .green : .secondary)
                statusRow("Tráfico", symbol: "car.side", value: trafficStatus, color: .secondary)
                SurroundingMapStatusRow(store: model.surroundingMap)
                Button("Mapas offline") { showsMapDownloads = true }
            }
            if model.isDemoActive {
                Section {
                    Label("La simulación utiliza datos de prueba.", systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                } footer: {
                    Text("Datos de vías © OpenStreetMap contributors")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(model.isDemoActive ? "Modo Demo" : "Navegando")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { deviceToolbarButton }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { navigationActionBar }
    }

    private func rideMetric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.title.weight(.semibold))
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
            Text(title).font(.subheadline).foregroundStyle(Color.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)，\(value)")
    }

    private var navigationActionBar: some View {
        VStack(spacing: 10) {
            Button(action: model.toggleNavigation) {
                HStack(spacing: 9) {
                    if model.isPlanningRoutePreview {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: model.isNavigationActive ? "stop.fill" : "location.fill")
                    }
                    Text(model.primaryActionTitle).fixedSize(horizontal: false, vertical: true)
                }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 34)
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 16))
            .controlSize(.large)
            .tint(model.isNavigationActive ? .red : .blue)
            .disabled(!model.isNavigationActive && (model.selectedPlace == nil || model.isPlanningRoutePreview))
            .accessibilityIdentifier("primary-navigation-action")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.bar)
    }

    // MARK: - Device sheet

    private var deviceToolbarButton: some View {
        Button {
            searchFocused = false
            showsDeviceDetails = true
        } label: { Image(systemName: "circle.circle") }
        .accessibilityLabel("Pantalla Moto")
        .accessibilityValue(deviceStatus)
        .accessibilityIdentifier("device-details-button")
    }

    private var deviceSummaryButton: some View {
        Button {
            searchFocused = false
            showsDeviceDetails = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "circle.circle")
                    .font(.title3)
                    .foregroundStyle(.blue)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pantalla Moto").foregroundStyle(Color.primary)
                    Text(deviceStatus).font(.subheadline).foregroundStyle(Color.secondary)
                }
                Spacer(minLength: 4)
                if model.deviceReady {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("device-summary-button")
    }

    private var deviceDetails: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "location.north.circle")
                            .font(.system(size: 64, weight: .ultraLight))
                            .foregroundStyle(.blue)
                            .accessibilityHidden(true)
                        Text(deviceName).font(.title2.weight(.semibold))
                        Text(deviceDetail)
                            .font(.subheadline)
                            .foregroundStyle(Color.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .listRowBackground(Color.clear)
                Section {
                    statusRow("Estado de Conexión", symbol: "antenna.radiowaves.left.and.right", value: deviceStatus,
                              color: model.deviceReady ? .green : .secondary)
                    Button(connectionActionTitle, action: model.toggleDeviceConnection)
                        .accessibilityIdentifier("device-connection-action")
                    if case .bluetoothUnavailable = model.device.connection {
                        Button("Abrir Ajustes", action: openSystemSettings)
                    }
                } footer: {
                    Text("Mantén la pantalla encendida y cerca del iPhone. Al conectar, se sincronizará automáticamente.")
                }
                Section("GPS y Ubicación") {
                    statusRow("Ubicación", symbol: "location", value: searchLocationStatus, color: .secondary)
                    if model.searchLocationStatus == .permissionDenied {
                        Button("Ir a Ajustes para activar ubicación", action: openSystemSettings)
                    }
                }
            }
            .navigationTitle("Pantalla Moto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { showsDeviceDetails = false }
                        .accessibilityIdentifier("device-details-done")
                }
            }
            .accessibilityIdentifier("device-details-sheet")
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func statusRow(_ title: String, symbol: String, value: String, color: Color) -> some View {
        LabeledContent {
            Text(value).foregroundStyle(color).multilineTextAlignment(.trailing)
        } label: {
            Label(title, systemImage: symbol).foregroundStyle(Color.primary)
        }
        .font(.body)
        .padding(.vertical, 4)
    }

    private func failureMessage(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.subheadline)
            .foregroundStyle(Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 6)
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }

    // MARK: - User-facing state

    private func placeSubtitle(_ place: PlaceSearchResult) -> String {
        let area = place.displayArea.isEmpty
            ? [place.city, place.district].filter { !$0.isEmpty }.joined(separator: " · ")
            : place.displayArea
        var parts = [area, place.address].filter { !$0.isEmpty }
        if let distance = place.distanceM, distance >= 0 {
            let distanceText = distance >= 1_000
                ? String(format: "%.1f km", distance / 1_000)
                : "\(Int(distance.rounded())) m"
            parts.append("A \(distanceText)")
        }
        return parts.isEmpty ? "Ver ruta" : parts.joined(separator: " · ")
    }

    private var deviceStatus: String {
        switch model.device.connection {
        case .connected: return model.deviceReady ? "Conectado" : "Preparando"
        case .scanning: return "Buscando pantalla"
        case .connecting: return "Conectando"
        case .failed: return "Error de conexión"
        case .bluetoothUnavailable: return "Bluetooth no disponible"
        case .idle: return "Desconectado"
        }
    }

    private var deviceName: String {
        switch model.device.connection {
        case let .connected(name), let .connecting(name): return name
        default: return "MOTO GPS"
        }
    }

    private var deviceDetail: String {
        switch model.device.connection {
        case .connected:
            return model.deviceReady ? "Pantalla lista para recibir indicaciones." : "Sincronizando navegación, un momento."
        case .failed:
            return "No se pudo conectar. Asegúrate de que la pantalla esté encendida y cerca."
        case .bluetoothUnavailable:
            return "Activa el Bluetooth y concede permisos a MOTO GPS."
        case .scanning, .connecting:
            return "Mantén la pantalla encendida cerca del iPhone."
        case .idle:
            return "Conecta la pantalla para ver el GPS en el manillar."
        }
    }

    private var connectionActionTitle: String {
        switch model.device.connection {
        case .connected: return "Desconectar"
        case .scanning: return "Detener búsqueda"
        case .connecting: return "Cancelar"
        case .failed: return "Reintentar conexión"
        case .idle, .bluetoothUnavailable: return "Conectar Pantalla"
        }
    }

    private var searchLocationStatus: String {
        switch model.searchLocationStatus {
        case .available: return "Disponible"
        case .preparing: return "Obteniendo"
        case .permissionDenied: return "Sin permiso"
        case .unavailable: return "No disponible"
        }
    }

    private var navigationTitle: String {
        if model.navigationFailure != nil { return "Atención a la navegación" }
        switch model.navigation.stateName {
        case "acquiring": return "Obteniendo ubicación"
        case "planning": return "Calculando ruta"
        case "rerouting": return "Recalculando ruta"
        case "arrived": return "¡Has llegado!"
        case "navigating": return model.isDemoActive ? "Simulación" : "Navegando"
        default: return "Listo para rodar"
        }
    }

    private var navigationDetail: String {
        if let failure = model.navigationFailure { return failure }
        if model.navigation.stateName == "navigating" {
            if model.isDemoActive { return "Simulación de ruta y pantalla activa." }
            return model.deviceReady
                ? "Pantalla conectada. Puedes bloquear el iPhone."
                : "Al conectar la pantalla, las indicaciones se sincronizarán."
        }
        return model.phaseDetail
    }

    private var navigationSymbol: String {
        if model.navigationFailure != nil { return "exclamationmark.triangle" }
        switch model.navigation.stateName {
        case "arrived": return "flag.checkered"
        case "rerouting": return "arrow.triangle.2.circlepath"
        case "navigating": return "location.north.fill"
        default: return "location.magnifyingglass"
        }
    }

    private var hasNavigationEstimate: Bool {
        ["navigating", "rerouting", "arrived"].contains(model.navigation.stateName)
    }

    private var remainingDuration: String {
        hasNavigationEstimate ? model.remainingDurationText : "—"
    }

    private var remainingDistance: String {
        hasNavigationEstimate ? model.remainingDistanceText : "—"
    }

    private var locationStatus: String {
        if model.isDemoActive { return "Simulación" }
        return model.navigation.hasUsableFix ? "Disponible" : "Obteniendo"
    }

    private var trafficStatus: String {
        if model.isDemoActive { return "Simulación" }
        if model.navigation.trafficRequestInFlight { return "Actualizando" }
        return model.navigation.networkName == "online" ? "En línea" : "Offline"
    }

    private func trafficTint(_ candidate: RoutePreviewCandidate) -> Color {
        switch candidate.trafficSummary {
        case "Tráfico pesado", "Congestión", "heavy": return .red
        case "Tráfico lento", "moderate": return .orange
        case "Tráfico fluido", "Despejado", "clear": return .green
        default: return .secondary
        }
    }
}
