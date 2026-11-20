package top.maler.motogps.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.DirectionsCar
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.MyLocation
import androidx.compose.material.icons.filled.Navigation
import androidx.compose.material.icons.filled.Place
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.automirrored.outlined.BluetoothSearching
import androidx.compose.material.icons.outlined.History
import androidx.compose.material.icons.outlined.Language
import androidx.compose.material.icons.outlined.Map
import androidx.compose.material.icons.outlined.PlayCircle
import androidx.compose.material.icons.outlined.PrivacyTip
import androidx.compose.material.icons.outlined.TravelExplore
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import top.maler.motogps.app.AppModel
import top.maler.motogps.ble.BleDeviceSnapshot
import top.maler.motogps.location.SearchLocationStatus
import top.maler.motogps.model.PlaceSearchResult
import top.maler.motogps.nav.JinanDemoFixture
import top.maler.motogps.nav.RoutePreviewCandidate
import top.maler.motogps.nav.TrafficSummary
import top.maler.motogps.nav.formatDistance

class ScreenActions(
    val openDevice: () -> Unit,
    val openMaps: () -> Unit,
    val openGateway: () -> Unit,
    val openDataUse: () -> Unit,
    val openAppSettings: () -> Unit,
    val requestLocation: () -> Unit,
)

// ------------------------------------------------------------- home

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(model: AppModel, actions: ScreenActions, searchFocus: FocusRequester) {
    val focusManager = LocalFocusManager.current
    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = { Text("MOTO GPS", fontWeight = FontWeight.SemiBold) },
                navigationIcon = {
                    IconButton(onClick = actions.openGateway, modifier = Modifier.testTag("gateway-settings-toolbar")) {
                        Icon(Icons.Default.Settings, contentDescription = "Ajustes de Gateway")
                    }
                },
                actions = { DeviceToolbarButton(model, actions.openDevice) },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background),
            )
        },
    ) { padding ->
        LazyColumn(
            Modifier.fillMaxSize().imePadding(),
            contentPadding = PaddingValues(top = padding.calculateTopPadding(), bottom = padding.calculateBottomPadding() + 24.dp),
        ) {
            if (!model.isGatewayConfigured) {
                section("gateway-setup", footer = "Configura la URL de tu gateway para buscar lugares y planear rutas.") {
                    ActionRow("Configurar Gateway", Icons.Outlined.Language, onClick = actions.openGateway)
                }
            }
            item(key = "search") {
                SearchField(
                    query = model.destinationQuery,
                    onQueryChange = model::updateDestinationQuery,
                    onSearch = {
                        model.submitDestinationSearch()
                        focusManager.clearFocus()
                    },
                    onClear = {
                        model.clearDestination()
                        searchFocus.requestFocus()
                    },
                    focusRequester = searchFocus,
                )
            }
            if (model.destinationQuery.isNotEmpty()) {
                section(
                    "results",
                    header = "Resultados de búsqueda",
                    footer = model.searchScopeText,
                ) {
                    when {
                        model.isSearchingPlaces -> Row(
                            Modifier.fillMaxWidth().heightIn(min = 56.dp).padding(horizontal = 16.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                            Text("Buscando lugares…", color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }

                        model.placeResults.isNotEmpty() -> model.placeResults.forEachIndexed { index, place ->
                            if (index > 0) SectionDivider()
                            PlaceRow(place, recent = false, modifier = Modifier.testTag("place-result-$index")) {
                                focusManager.clearFocus()
                                model.selectPlace(place)
                            }
                        }

                        else -> EmptyState(
                            Icons.Default.Search,
                            if (model.placeSearchFailure == null) "Escribe un destino" else "Sin resultados",
                            model.placeSearchFailure ?: "Escribe un lugar o dirección, ej: 'Parque 93'",
                        ) {
                            if (model.placeSearchFailure != null) {
                                TextButton(onClick = model::submitDestinationSearch) { Text("Reintentar") }
                            }
                        }
                    }
                }
                if (model.searchLocationStatus == SearchLocationStatus.PERMISSION_DENIED) {
                    item(key = "location-permission") {
                        TextButton(onClick = actions.requestLocation, modifier = Modifier.padding(horizontal = 20.dp)) {
                            Text("Activar GPS para ordenar por cercanía")
                        }
                    }
                }
            } else {
                if (model.recentPlaces.isEmpty()) {
                    item(key = "empty") {
                        EmptyState(Icons.Outlined.Map, "Elige tu destino", "Busca cualquier lugar o dirección y sal a rodar.")
                    }
                } else {
                    section(
                        "recent",
                        header = "Búsquedas recientes",
                        headerAction = { TextButton(onClick = model::clearRecentPlaces) { Text("Borrar") } },
                    ) {
                        model.recentPlaces.forEachIndexed { index, place ->
                            if (index > 0) SectionDivider()
                            PlaceRow(place, recent = true, modifier = Modifier.testTag("recent-place-$index")) {
                                focusManager.clearFocus()
                                model.selectPlace(place)
                            }
                        }
                    }
                }
                section("tools", footer = "Al conectar la pantalla AMOLED, la navegación se sincroniza.") {
                    DeviceSummaryRow(model, actions.openDevice)
                    SectionDivider()
                    ActionRow(
                        "Mapas y offline",
                        Icons.Outlined.Map,
                        subtitle = "Carga mapas cercanos o guarda ciudades",
                        onClick = actions.openMaps,
                    )
                    SectionDivider()
                    ActionRow(
                        "Ruta de demostración",
                        Icons.Outlined.PlayCircle,
                        subtitle = "Probar la pantalla con una ruta demo",
                        showChevron = false,
                        onClick = {
                            focusManager.clearFocus()
                            model.startDemoNavigation()
                        },
                    )
                }
                section("settings") {
                    ActionRow("Ajustes de Gateway", Icons.Outlined.Language, onClick = actions.openGateway)
                    SectionDivider()
                    ActionRow("Privacidad y datos", Icons.Outlined.PrivacyTip, onClick = actions.openDataUse)
                }
            }
        }
    }
}

@Composable
private fun SearchField(
    query: String,
    onQueryChange: (String) -> Unit,
    onSearch: () -> Unit,
    onClear: () -> Unit,
    focusRequester: FocusRequester,
) {
    OutlinedTextField(
        value = query,
        onValueChange = onQueryChange,
        placeholder = { Text("Buscar destino o dirección") },
        leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
        trailingIcon = {
            if (query.isNotEmpty()) {
                IconButton(onClick = onClear) { Icon(Icons.Default.Close, contentDescription = "Borrar") }
            }
        },
        singleLine = true,
        shape = RoundedCornerShape(14.dp),
        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
        keyboardActions = KeyboardActions(onSearch = { onSearch() }),
        colors = OutlinedTextFieldDefaults.colors(
            focusedContainerColor = MaterialTheme.colorScheme.surfaceContainer,
            unfocusedContainerColor = MaterialTheme.colorScheme.surfaceContainer,
            unfocusedBorderColor = Color.Transparent,
        ),
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp)
            .focusRequester(focusRequester)
            .testTag("destination-search-field"),
    )
}

@Composable
private fun PlaceRow(place: PlaceSearchResult, recent: Boolean, modifier: Modifier = Modifier, onClick: () -> Unit) {
    ActionRow(
        title = place.name,
        icon = if (recent) Icons.Outlined.History else Icons.Default.Place,
        iconTint = if (recent) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.primary,
        subtitle = placeSubtitle(place),
        onClick = onClick,
    )
}

fun placeSubtitle(place: PlaceSearchResult): String {
    val area = place.displayArea.ifEmpty { listOf(place.city, place.district).filter { it.isNotEmpty() }.joinToString(" · ") }
    val parts = listOf(area, place.address).filter { it.isNotEmpty() }.toMutableList()
    place.distanceM?.takeIf { it >= 0 }?.let { parts += "A ${formatDistance(it)}" }
    return if (parts.isEmpty()) "Ver ruta" else parts.joinToString(" · ")
}

// ------------------------------------------------------------- route preview

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RoutePreviewScreen(model: AppModel, actions: ScreenActions, onChangeDestination: () -> Unit) {
    val place = model.selectedPlace ?: return
    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = { Text("Ruta") },
                navigationIcon = {
                    IconButton(onClick = model::clearDestination) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Atrás")
                    }
                },
                actions = {
                    TextButton(onClick = onChangeDestination, modifier = Modifier.testTag("destination-change-button")) { Text("Cambiar") }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background),
            )
        },
        bottomBar = { NavigationActionBar(model) },
    ) { padding ->
        LazyColumn(Modifier.fillMaxSize(), contentPadding = padding) {
            section("destination", header = "Desde mi ubicación actual") {
                ActionRow(place.name, Icons.Default.LocationOn, iconTint = MotoColors.Red, subtitle = placeSubtitle(place), showChevron = false)
            }
            when {
                model.isPlanningRoutePreview -> section("loading") {
                    Row(
                        Modifier.fillMaxWidth().padding(16.dp).testTag("route-preview-loading"),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(14.dp),
                    ) {
                        CircularProgressIndicator(Modifier.size(24.dp), strokeWidth = 2.5.dp)
                        Column {
                            Text("Calculando ruta...")
                            Text("Consultando tráfico y opciones...", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }

                model.hasRoutePreview -> {
                    section("map") {
                        RouteOverviewMap(
                            candidates = model.routePreviewCandidates,
                            selectedId = model.selectedRoutePreviewId,
                            origin = model.routePreviewOrigin,
                            destination = place.location,
                            description = "Ruta hacia ${place.name}",
                            modifier = Modifier.fillMaxWidth().height(260.dp).testTag("route-preview-map"),
                        )
                    }
                    section("options", header = "Opciones de ruta", footer = "Ruta en moto · El tiempo varía según el tráfico") {
                        model.routePreviewCandidates.forEachIndexed { index, candidate ->
                            if (index > 0) SectionDivider()
                            RouteOptionRow(candidate, selected = candidate.id == model.selectedRoutePreviewId) {
                                model.selectRoutePreview(candidate.id)
                            }
                        }
                    }
                    section("downloads") {
                        ActionRow("Mapas y offline", Icons.Outlined.Map, subtitle = "Guarda el mapa a lo largo de esta ruta", onClick = actions.openMaps)
                    }
                }

                model.routePreviewFailure != null -> section("failure") {
                    EmptyState(Icons.Default.Warning, "No se pudo calcular la ruta", model.routePreviewFailure.orEmpty()) {
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            if (model.searchLocationStatus == SearchLocationStatus.PERMISSION_DENIED) {
                                TextButton(onClick = actions.requestLocation) { Text("Activar GPS") }
                            } else {
                                TextButton(onClick = model::planRoutePreview) { Text("Recalcular") }
                            }
                        }
                    }
                }
            }
            model.navigationFailure?.let { failure ->
                section("navigation-failure") { FailureMessage(failure) }
            }
        }
    }
}

@Composable
private fun RouteOptionRow(candidate: RoutePreviewCandidate, selected: Boolean, onClick: () -> Unit) {
    val trafficColor = when (candidate.trafficSummary) {
        TrafficSummary.HEAVY -> MotoColors.Red
        TrafficSummary.PARTIAL -> MotoColors.Orange
        TrafficSummary.CLEAR -> MotoColors.Green
        TrafficSummary.NONE -> MaterialTheme.colorScheme.onSurfaceVariant
    }
    Row(
        Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 12.dp)
            .testTag("route-option-${candidate.ordinal}"),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                candidate.title,
                style = MaterialTheme.typography.bodyMedium,
                color = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(candidate.durationText, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.SemiBold)
                Text(candidate.distanceText, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Icon(Icons.Default.DirectionsCar, contentDescription = null, tint = trafficColor, modifier = Modifier.size(16.dp))
                Text(candidate.trafficSummary.text, style = MaterialTheme.typography.bodyMedium, color = trafficColor)
            }
        }
        Icon(
            if (selected) Icons.Default.CheckCircle else Icons.Default.RadioButtonUnchecked,
            contentDescription = if (selected) "Seleccionada" else null,
            tint = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outlineVariant,
            modifier = Modifier.size(28.dp),
        )
    }
}

@Composable
private fun NavigationActionBar(model: AppModel) {
    Surface(color = MaterialTheme.colorScheme.surfaceContainer, shadowElevation = 4.dp) {
        Button(
            onClick = model::toggleNavigation,
            enabled = model.isNavigationActive || (model.selectedPlace != null && !model.isPlanningRoutePreview),
            shape = RoundedCornerShape(16.dp),
            colors = ButtonDefaults.buttonColors(
                containerColor = if (model.isNavigationActive) MotoColors.Red else MaterialTheme.colorScheme.primary,
            ),
            modifier = Modifier
                .fillMaxWidth()
                .navigationBarsPadding()
                .padding(horizontal = 20.dp, vertical = 12.dp)
                .height(54.dp)
                .testTag("primary-navigation-action"),
        ) {
            if (model.isPlanningRoutePreview) {
                CircularProgressIndicator(Modifier.size(18.dp), color = Color.White, strokeWidth = 2.dp)
            } else {
                Icon(if (model.isNavigationActive) Icons.Default.Stop else Icons.Default.Navigation, contentDescription = null)
            }
            Spacer(Modifier.width(8.dp))
            Text(model.primaryActionTitle, style = MaterialTheme.typography.titleMedium)
        }
    }
}

// ------------------------------------------------------------- active ride

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ActiveNavigationScreen(model: AppModel, actions: ScreenActions) {
    val nav = model.navigation
    val hasEstimate = nav.stateName in setOf("navigating", "rerouting", "arrived")
    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = { Text(if (model.isDemoActive) "Ruta Demo" else "Navegando") },
                actions = { DeviceToolbarButton(model, actions.openDevice) },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background),
            )
        },
        bottomBar = { NavigationActionBar(model) },
    ) { padding ->
        LazyColumn(Modifier.fillMaxSize(), contentPadding = padding) {
            item(key = "hero") { RideHero(model) }
            section("destination") {
                ActionRow(
                    title = model.activeDestinationName,
                    icon = Icons.Default.Flag,
                    subtitle = if (model.isDemoActive) "Destino de prueba" else "Destino",
                    showChevron = false,
                )
                SectionDivider()
                Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp)) {
                    RideMetric("Tiempo restante", if (hasEstimate) model.remainingDurationText else "—", Modifier.weight(1f))
                    RideMetric("Distancia restante", if (hasEstimate) model.remainingDistanceText else "—", Modifier.weight(1f))
                }
            }
            section("status", header = "Estado de navegación") {
                DeviceSummaryRow(model, actions.openDevice)
                SectionDivider()
                StatusRow(
                    "GPS del celular",
                    Icons.Default.MyLocation,
                    when {
                        model.isDemoActive -> "Simulado"
                        nav.hasUsableFix -> "Activo"
                        else -> "Buscando..."
                    },
                    if (nav.hasUsableFix) MotoColors.Green else MaterialTheme.colorScheme.onSurfaceVariant,
                )
                SectionDivider()
                StatusRow(
                    "Tráfico",
                    Icons.Default.DirectionsCar,
                    when {
                        model.isDemoActive -> "Demo"
                        nav.trafficRequestInFlight -> "Actualizando..."
                        nav.networkName == "online" -> "En vivo"
                        else -> "Offline"
                    },
                )
                SectionDivider()
                StatusRow("Mapa cercano", Icons.Outlined.Map, model.surroundingMap.statusText)
                SectionDivider()
                ActionRow("Administrar mapas offline", Icons.Outlined.TravelExplore, onClick = actions.openMaps)
            }
            if (model.isDemoActive) {
                section("demo", footer = "Datos de mapa © OpenStreetMap contributors") {
                    ActionRow("Esta es una ruta de demostración para pruebas.", Icons.Default.Info, showChevron = false)
                }
            }
        }
    }
}

@Composable
private fun RideHero(model: AppModel) {
    val nav = model.navigation
    val failure = model.navigationFailure
    val title = when {
        failure != null -> "Atención requerida"
        nav.stateName == "acquiring" -> "Buscando señal GPS..."
        nav.stateName == "planning" -> "Calculando ruta..."
        nav.stateName == "rerouting" -> "Recalculando ruta..."
        nav.stateName == "arrived" -> "¡Llegaste a tu destino!"
        nav.stateName == "navigating" -> if (model.isDemoActive) "Ruta Demo" else "Navegando"
        else -> "Listo para rodar"
    }
    val detail = when {
        failure != null -> failure
        nav.stateName == "navigating" && model.isDemoActive -> "Simulando navegación en la pantalla circular."
        nav.stateName == "navigating" -> if (model.deviceReady) "Pantalla AMOLED conectada. Puedes bloquear el celular." else "Sincronizando con pantalla AMOLED..."
        else -> model.phaseDetail
    }
    Column(
        Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        if (nav.stateName == "navigating" && nav.hasNextManeuver && failure == null) {
            Surface(shape = RoundedCornerShape(20.dp), color = MaterialTheme.colorScheme.surfaceContainer, modifier = Modifier.fillMaxWidth()) {
                Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                    ManeuverBadge(nav.maneuverTypeName)
                    Spacer(Modifier.width(16.dp))
                    Column(Modifier.weight(1f)) {
                        Text(formatDistance(nav.distanceToManeuverM), style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.SemiBold)
                        Text(
                            nav.instructionText.ifEmpty { nav.roadName },
                            style = MaterialTheme.typography.bodyLarge,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                        )
                        if (nav.roadName.isNotEmpty() && nav.instructionText.isNotEmpty()) {
                            Text(nav.roadName, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            }
        } else {
            Box(
                Modifier.size(76.dp).background(MaterialTheme.colorScheme.primary.copy(alpha = 0.1f), CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                if (nav.stateName in setOf("acquiring", "planning", "rerouting") && failure == null) {
                    CircularProgressIndicator(Modifier.size(36.dp), strokeWidth = 3.dp)
                } else {
                    Icon(
                        when {
                            failure != null -> Icons.Default.Warning
                            nav.stateName == "arrived" -> Icons.Default.Flag
                            else -> Icons.Default.Navigation
                        },
                        contentDescription = null,
                        tint = if (failure == null) MaterialTheme.colorScheme.primary else MotoColors.Orange,
                        modifier = Modifier.size(36.dp),
                    )
                }
            }
        }
        Text(title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
        Text(detail, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
        if (model.isDemoActive && nav.stateName == "navigating") {
            Text(JinanDemoFixture.ROAD_ATTRIBUTION, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun RideMetric(title: String, value: String, modifier: Modifier = Modifier) {
    Column(modifier) {
        Text(value, style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.SemiBold)
        Text(title, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
fun FailureMessage(message: String) {
    ActionRow(message, Icons.Default.Warning, iconTint = MotoColors.Orange, showChevron = false)
}

// ------------------------------------------------------------- device summary

@Composable
fun DeviceToolbarButton(model: AppModel, onClick: () -> Unit) {
    IconButton(onClick = onClick, modifier = Modifier.testTag("device-details-button")) {
        Box {
            Icon(Icons.AutoMirrored.Outlined.BluetoothSearching, contentDescription = "我的圆屏，${deviceStatusText(model.device)}")
            if (model.deviceReady) {
                Box(Modifier.size(8.dp).background(MotoColors.Green, CircleShape).align(Alignment.TopEnd))
            }
        }
    }
}

@Composable
fun DeviceSummaryRow(model: AppModel, onClick: () -> Unit) {
    ActionRow(
        title = "我的圆屏",
        icon = Icons.AutoMirrored.Outlined.BluetoothSearching,
        subtitle = deviceStatusText(model.device),
        trailing = {
            if (model.deviceReady) {
                Icon(Icons.Default.CheckCircle, contentDescription = null, tint = MotoColors.Green, modifier = Modifier.padding(end = 4.dp))
            }
        },
        onClick = onClick,
    )
}

fun deviceStatusText(device: BleDeviceSnapshot): String = when (val connection = device.connection) {
    is BleDeviceSnapshot.Connection.Connected -> if (device.isReady) "已连接" else "正在准备"
    BleDeviceSnapshot.Connection.Scanning -> "正在寻找圆屏"
    is BleDeviceSnapshot.Connection.Connecting -> connection.detail ?: "正在连接"
    is BleDeviceSnapshot.Connection.Failed -> "连接未成功"
    BleDeviceSnapshot.Connection.BluetoothUnavailable -> "蓝牙不可用"
    BleDeviceSnapshot.Connection.PermissionRequired -> "需要蓝牙权限"
    BleDeviceSnapshot.Connection.Idle -> "未连接"
}
