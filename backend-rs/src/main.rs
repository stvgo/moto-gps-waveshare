use axum::{
    body::Body,
    extract::{Query, State},
    http::{header, HeaderMap, HeaderValue, StatusCode},
    response::{IntoResponse, Response},
    routing::{get, post},
    Json, Router,
};
use serde::{Deserialize, Serialize};
use std::{env, net::SocketAddr, path::PathBuf, sync::Arc, time::Duration};
use tower_http::cors::CorsLayer;
use tracing::{error, info};
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

#[derive(Clone)]
struct AppState {
    http_client: reqwest::Client,
    mapbox_token: String,
    apk_path: PathBuf,
}

#[derive(Deserialize)]
struct PlacesQuery {
    keywords: Option<String>,
    #[serde(rename = "origin.longitude_deg")]
    origin_lon: Option<f64>,
    #[serde(rename = "origin.latitude_deg")]
    origin_lat: Option<f64>,
}

#[derive(Deserialize)]
struct RouteRequest {
    protocol_version: Option<u32>,
    request_id: u64,
    origin: Point,
    destination: Point,
    #[allow(dead_code)]
    is_reroute: Option<bool>,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
struct Point {
    longitude_deg: f64,
    latitude_deg: f64,
}

#[derive(Serialize, Clone, Debug)]
struct Maneuver {
    id: u32,
    #[serde(rename = "type")]
    maneuver_type: String,
    route_offset_m: f64,
    road_name: String,
    instruction: String,
    roundabout_exit: u32,
}

#[derive(Serialize, Clone, Debug)]
struct TrafficSegment {
    start_offset_m: f64,
    end_offset_m: f64,
    level: String,
}

#[derive(Serialize, Clone, Debug)]
struct RouteBundle {
    schema_version: u32,
    route_id: String,
    provider: String,
    coordinate_system: String,
    generated_at_ms: u64,
    total_distance_m: f64,
    total_duration_s: u32,
    polyline: Vec<Point>,
    maneuvers: Vec<Maneuver>,
    traffic: Vec<TrafficSegment>,
}

#[derive(Serialize)]
struct PlaceItem {
    id: String,
    name: String,
    address: String,
    city: String,
    district: String,
    display_area: String,
    location: Point,
    #[serde(skip_serializing_if = "Option::is_none")]
    distance_m: Option<u32>,
}

#[derive(Serialize)]
struct PlacesResponse {
    protocol_version: u32,
    query: String,
    places: Vec<PlaceItem>,
}

#[derive(Serialize)]
struct RouteEnvelope {
    protocol_version: u32,
    request_id: u64,
    route: RouteBundle,
}

#[derive(Serialize)]
struct RouteOptionsEnvelope {
    protocol_version: u32,
    request_id: u64,
    routes: Vec<RouteBundle>,
}

#[tokio::main]
async fn main() {
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "moto_gps_backend=info,tower_http=info".into()),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

    let mapbox_token = env::var("MAPBOX_ACCESS_TOKEN").unwrap_or_default();
    if mapbox_token.is_empty() {
        tracing::warn!("⚠️ MAPBOX_ACCESS_TOKEN is not set. Please set MAPBOX_ACCESS_TOKEN in environment / Railway.");
    }
    
    let apk_path = env::var("MOTO_APK_PATH")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("app-debug.apk"));

    let http_client = reqwest::Client::builder()
        .timeout(Duration::from_secs(8))
        .build()
        .expect("failed to create reqwest client");

    let state = Arc::new(AppState {
        http_client,
        mapbox_token,
        apk_path,
    });

    let app = Router::new()
        .route("/", get(root_handler))
        .route("/healthz", get(healthz))
        .route("/v1/places", get(search_places))
        .route("/v1/route-options", post(route_options))
        .route("/v1/routes", post(single_route))
        .route("/moto-gps.apk", get(serve_apk))
        .route("/app-debug.apk", get(serve_apk))
        .layer(CorsLayer::permissive())
        .with_state(state);

    let env_port: Option<u16> = env::var("PORT")
        .ok()
        .and_then(|p| p.parse().ok());

    let mut ports: Vec<u16> = Vec::new();
    if let Some(p) = env_port {
        ports.push(p);
    }
    for p in [8080, 8787] {
        if !ports.contains(&p) {
            ports.push(p);
        }
    }

    let mut handles = Vec::new();
    for port in ports {
        let addr = SocketAddr::from(([0, 0, 0, 0], port));
        let app_clone = app.clone();
        match tokio::net::TcpListener::bind(addr).await {
            Ok(listener) => {
                info!("🚀 MOTO GPS Rust Backend running on http://{}", addr);
                handles.push(tokio::spawn(async move {
                    let _ = axum::serve(listener, app_clone).await;
                }));
            }
            Err(e) => {
                info!("Port {} not available or could not bind (skipping): {}", port, e);
            }
        }
    }

    if handles.is_empty() {
        panic!("Failed to bind to any HTTP port!");
    }

    std::future::pending::<()>().await;
}

async fn root_handler() -> impl IntoResponse {
    axum::response::Html(r#"<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>MOTO GPS Gateway</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #0d1117; color: #c9d1d9; display: flex; justify-content: center; align-items: center; min-height: 100vh; margin: 0; }
        .card { background: #161b22; border: 1px solid #30363d; border-radius: 12px; padding: 32px; max-width: 520px; width: 90%; box-shadow: 0 8px 24px rgba(0,0,0,0.5); text-align: center; }
        h1 { color: #58a6ff; margin-top: 0; font-size: 26px; }
        .badge { display: inline-block; padding: 6px 14px; border-radius: 20px; font-weight: 600; font-size: 14px; background: #238636; color: #fff; margin-bottom: 20px; }
        p { color: #8b949e; line-height: 1.6; }
        .endpoints { text-align: left; background: #0d1117; border-radius: 8px; padding: 14px 18px; margin: 20px 0; font-family: monospace; font-size: 13px; }
        .btn { display: inline-block; background: #238636; color: #fff; text-decoration: none; padding: 12px 24px; border-radius: 8px; font-weight: 600; transition: background 0.2s; margin-top: 10px; }
        .btn:hover { background: #2ea043; }
    </style>
</head>
<body>
    <div class="card">
        <h1>🏍️ MOTO GPS Gateway</h1>
        <div class="badge">● Online (Rust Axum Engine)</div>
        <p>Servidor de navegación de alta velocidad para Waveshare ESP32-S3 y teléfonos móviles.</p>
        <div class="endpoints">
            <div>🟢 <strong>GET</strong> /healthz - Estado y diagnóstico</div>
            <div>🟢 <strong>GET</strong> /v1/places - Búsqueda de lugares</div>
            <div>🟢 <strong>POST</strong> /v1/routes - Cálculo de rutas Mapbox</div>
            <div>📲 <strong>GET</strong> /moto-gps.apk - Descarga directa del APK</div>
        </div>
        <a class="btn" href="/moto-gps.apk">📲 Descargar App Android (APK)</a>
    </div>
</body>
</html>"#)
}

async fn healthz() -> impl IntoResponse {
    Json(serde_json::json!({
        "status": "ok",
        "ready_for_live_navigation": true,
        "provider": "mapbox",
        "engine": "rust-axum",
        "capabilities": {
            "route_planning": true,
            "route_traffic": true,
            "road_speed_limits": false,
            "traffic_light_countdown": false,
            "surrounding_map": false,
            "map_city_search": true
        },
        "map_source": { "enabled": false }
    }))
}

async fn search_places(
    State(state): State<Arc<AppState>>,
    Query(params): Query<PlacesQuery>,
) -> impl IntoResponse {
    let keywords = params.keywords.unwrap_or_default().trim().to_string();
    if keywords.is_empty() {
        return Json(PlacesResponse {
            protocol_version: 1,
            query: keywords,
            places: vec![],
        });
    }

    let origin = match (params.origin_lon, params.origin_lat) {
        (Some(lon), Some(lat)) => Some(Point { longitude_deg: lon, latitude_deg: lat }),
        _ => None,
    };

    // 1. Try Komoot Photon (OpenStreetMap)
    if let Some(mut places) = search_photon(&state.http_client, &keywords, origin.as_ref()).await {
        if !places.is_empty() {
            places.truncate(10);
            return Json(PlacesResponse {
                protocol_version: 1,
                query: keywords,
                places,
            });
        }
    }

    // 2. Fallback to Mapbox Geocoding
    let places = search_mapbox(&state.http_client, &state.mapbox_token, &keywords, origin.as_ref())
        .await
        .unwrap_or_default();

    Json(PlacesResponse {
        protocol_version: 1,
        query: keywords,
        places,
    })
}

async fn search_photon(
    client: &reqwest::Client,
    keywords: &str,
    origin: Option<&Point>,
) -> Option<Vec<PlaceItem>> {
    let (lat, lon) = match origin {
        Some(p) => (p.latitude_deg.to_string(), p.longitude_deg.to_string()),
        None => ("4.711".to_string(), "-74.072".to_string()),
    };

    let url = format!(
        "https://photon.komoot.io/api/?q={}&lat={}&lon={}&limit=12",
        urlencoding::encode(keywords),
        lat,
        lon
    );

    let res = client
        .get(&url)
        .header("User-Agent", "MotoGPS/1.0")
        .send()
        .await
        .ok()?;

    if !res.status().is_success() {
        return None;
    }

    let json: serde_json::Value = res.json().await.ok()?;
    let features = json.get("features")?.as_array()?;
    let mut results = Vec::new();

    for f in features {
        let props = f.get("properties")?;
        let country = props.get("country").and_then(|v| v.as_str()).unwrap_or("");
        let countrycode = props.get("countrycode").and_then(|v| v.as_str()).unwrap_or("");
        if !country.is_empty() && country != "Colombia" && countrycode != "CO" {
            continue;
        }

        let coords = f.get("geometry")?.get("coordinates")?.as_array()?;
        if coords.len() < 2 {
            continue;
        }
        let pt = Point {
            longitude_deg: coords[0].as_f64()?,
            latitude_deg: coords[1].as_f64()?,
        };

        let name = props
            .get("name")
            .and_then(|v| v.as_str())
            .unwrap_or(keywords);
        let city = props
            .get("city")
            .or_else(|| props.get("district"))
            .or_else(|| props.get("state"))
            .and_then(|v| v.as_str())
            .unwrap_or("Bogotá");
        let street = props.get("street").and_then(|v| v.as_str()).unwrap_or("");
        let address = if !street.is_empty() {
            format!("{}, {}", street, city)
        } else {
            name.to_string()
        };

        let dist = origin.map(|o| distance_m(o, &pt));

        results.push(PlaceItem {
            id: props.get("osm_id").map(|v| v.to_string()).unwrap_or_else(|| name.to_string()),
            name: name.to_string(),
            address,
            city: city.to_string(),
            district: String::new(),
            display_area: city.to_string(),
            location: pt,
            distance_m: dist,
        });
    }

    Some(results)
}

async fn search_mapbox(
    client: &reqwest::Client,
    token: &str,
    keywords: &str,
    origin: Option<&Point>,
) -> Option<Vec<PlaceItem>> {
    let mut url = format!(
        "https://api.mapbox.com/geocoding/v5/mapbox.places/{}.json?access_token={}&country=co&limit=8",
        urlencoding::encode(keywords),
        token
    );
    if let Some(p) = origin {
        url.push_str(&format!("&proximity={},{}", p.longitude_deg, p.latitude_deg));
    }

    let res = client.get(&url).send().await.ok()?;
    if !res.status().is_success() {
        return None;
    }

    let json: serde_json::Value = res.json().await.ok()?;
    let features = json.get("features")?.as_array()?;
    let mut results = Vec::new();

    for f in features {
        let center = f.get("center")?.as_array()?;
        if center.len() < 2 {
            continue;
        }
        let pt = Point {
            longitude_deg: center[0].as_f64()?,
            latitude_deg: center[1].as_f64()?,
        };
        let name = f.get("text").and_then(|v| v.as_str()).unwrap_or("");
        let place_name = f.get("place_name").and_then(|v| v.as_str()).unwrap_or("");
        let id = f.get("id").and_then(|v| v.as_str()).unwrap_or("");

        let dist = origin.map(|o| distance_m(o, &pt));

        results.push(PlaceItem {
            id: id.to_string(),
            name: name.to_string(),
            address: place_name.to_string(),
            city: "Colombia".to_string(),
            district: String::new(),
            display_area: place_name.to_string(),
            location: pt,
            distance_m: dist,
        });
    }

    Some(results)
}

async fn route_options(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<RouteRequest>,
) -> Result<Json<RouteOptionsEnvelope>, StatusCode> {
    let routes = fetch_mapbox_routes(&state.http_client, &state.mapbox_token, &payload.origin, &payload.destination)
        .await
        .map_err(|e| {
            error!("Mapbox directions error: {:?}", e);
            StatusCode::BAD_GATEWAY
        })?;

    Ok(Json(RouteOptionsEnvelope {
        protocol_version: 1,
        request_id: payload.request_id,
        routes,
    }))
}

async fn single_route(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<RouteRequest>,
) -> Result<Json<RouteEnvelope>, StatusCode> {
    let routes = fetch_mapbox_routes(&state.http_client, &state.mapbox_token, &payload.origin, &payload.destination)
        .await
        .map_err(|e| {
            error!("Mapbox directions error: {:?}", e);
            StatusCode::BAD_GATEWAY
        })?;

    let primary = routes.into_iter().next().ok_or(StatusCode::NOT_FOUND)?;

    Ok(Json(RouteEnvelope {
        protocol_version: 1,
        request_id: payload.request_id,
        route: primary,
    }))
}

async fn fetch_mapbox_routes(
    client: &reqwest::Client,
    token: &str,
    origin: &Point,
    dest: &Point,
) -> Result<Vec<RouteBundle>, String> {
    let url = format!(
        "https://api.mapbox.com/directions/v5/mapbox/driving-traffic/{},{};{},{}?access_token={}&geometries=geojson&steps=true&overview=full&alternatives=true&annotations=congestion",
        origin.longitude_deg, origin.latitude_deg, dest.longitude_deg, dest.latitude_deg, token
    );

    let res = client
        .get(&url)
        .send()
        .await
        .map_err(|e| e.to_string())?;

    if !res.status().is_success() {
        return Err(format!("Mapbox status: {}", res.status()));
    }

    let json: serde_json::Value = res.json().await.map_err(|e| e.to_string())?;
    let raw_routes = json
        .get("routes")
        .and_then(|v| v.as_array())
        .ok_or_else(|| "No routes found".to_string())?;

    let now_ms = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64;

    let mut bundles = Vec::new();
    for r in raw_routes.iter().take(3) {
        let total_distance_m = r.get("distance").and_then(|v| v.as_f64()).unwrap_or(0.0);
        let total_duration_s = r.get("duration").and_then(|v| v.as_f64()).unwrap_or(0.0).round() as u32;

        let mut polyline = Vec::new();
        if let Some(coords) = r.get("geometry").and_then(|g| g.get("coordinates")).and_then(|c| c.as_array()) {
            for c in coords {
                if let (Some(lon), Some(lat)) = (c.get(0).and_then(|v| v.as_f64()), c.get(1).and_then(|v| v.as_f64())) {
                    polyline.push(Point { longitude_deg: lon, latitude_deg: lat });
                }
            }
        }

        let mut maneuvers = Vec::new();
        let mut traffic = Vec::new();
        let mut maneuver_id = 1;
        let mut route_offset_m = 0.0;

        if let Some(legs) = r.get("legs").and_then(|l| l.as_array()) {
            for leg in legs {
                if let Some(steps) = leg.get("steps").and_then(|s| s.as_array()) {
                    for step in steps {
                        let step_dist = step.get("distance").and_then(|v| v.as_f64()).unwrap_or(0.0);
                        let name = step.get("name").and_then(|v| v.as_str()).unwrap_or("");
                        let instruction = step.get("maneuver").and_then(|m| m.get("instruction")).and_then(|v| v.as_str()).unwrap_or("");
                        let man_type = step.get("maneuver").and_then(|m| m.get("type")).and_then(|v| v.as_str()).unwrap_or("");
                        let man_modifier = step.get("maneuver").and_then(|m| m.get("modifier")).and_then(|v| v.as_str()).unwrap_or("");
                        let exit = step.get("maneuver").and_then(|m| m.get("exit")).and_then(|v| v.as_u64()).unwrap_or(0) as u32;

                        maneuvers.push(Maneuver {
                            id: maneuver_id,
                            maneuver_type: map_maneuver(man_type, man_modifier),
                            route_offset_m: (route_offset_m + step_dist).round(),
                            road_name: name.to_string(),
                            instruction: instruction.to_string(),
                            roundabout_exit: exit,
                        });
                        maneuver_id += 1;
                        route_offset_m += step_dist;
                    }
                }

                if let Some(congestions) = leg.get("annotation").and_then(|a| a.get("congestion")).and_then(|c| c.as_array()) {
                    if !congestions.is_empty() {
                        let leg_distance = leg.get("distance").and_then(|v| v.as_f64()).unwrap_or(0.0);
                        let seg_dist = leg_distance / congestions.len() as f64;
                        let mut seg_start = 0.0;
                        for c in congestions {
                            let seg_end = seg_start + seg_dist;
                            traffic.push(TrafficSegment {
                                start_offset_m: seg_start.round(),
                                end_offset_m: seg_end.round(),
                                level: map_traffic(c.as_str().unwrap_or("")),
                            });
                            seg_start = seg_end;
                        }
                    }
                }
            }
        }

        let route_id = format!("mapbox-{}-{}-{}", now_ms, total_distance_m as u64, total_duration_s);

        bundles.push(RouteBundle {
            schema_version: 1,
            route_id,
            provider: "amap".to_string(), // Keep "amap" for schema protocol compatibility
            coordinate_system: "GCJ-02".to_string(),
            generated_at_ms: now_ms,
            total_distance_m: total_distance_m.round(),
            total_duration_s,
            polyline,
            maneuvers,
            traffic,
        });
    }

    Ok(bundles)
}

fn map_maneuver(mtype: &str, modifier: &str) -> String {
    match mtype {
        "arrive" => "arrive".to_string(),
        "roundabout" | "rotary" => {
            if modifier == "exit" { "exit".to_string() } else { "roundabout".to_string() }
        }
        _ => {
            if modifier.contains("right") {
                if modifier.contains("sharp") { "sharp_right".to_string() }
                else if modifier.contains("slight") { "slight_right".to_string() }
                else if modifier.contains("uturn") { "u_turn_right".to_string() }
                else { "right".to_string() }
            } else if modifier.contains("left") {
                if modifier.contains("sharp") { "sharp_left".to_string() }
                else if modifier.contains("slight") { "slight_left".to_string() }
                else if modifier.contains("uturn") { "u_turn_left".to_string() }
                else { "left".to_string() }
            } else {
                "continue".to_string()
            }
        }
    }
}

fn map_traffic(c: &str) -> String {
    match c.to_lowercase().as_str() {
        "severe" => "severe".to_string(),
        "heavy" => "congested".to_string(),
        "moderate" => "slow".to_string(),
        _ => "free_flow".to_string(),
    }
}

fn distance_m(p1: &Point, p2: &Point) -> u32 {
    let r = 6371000.0;
    let d_lat = (p2.latitude_deg - p1.latitude_deg).to_radians();
    let d_lon = (p2.longitude_deg - p1.longitude_deg).to_radians();
    let a = (d_lat / 2.0).sin().powi(2)
        + p1.latitude_deg.to_radians().cos() * p2.latitude_deg.to_radians().cos() * (d_lon / 2.0).sin().powi(2);
    let c = 2.0 * a.sqrt().atan2((1.0 - a).sqrt());
    (r * c).round() as u32
}

async fn serve_apk(State(state): State<Arc<AppState>>) -> impl IntoResponse {
    let path = &state.apk_path;
    let file = match tokio::fs::File::open(path).await {
        Ok(f) => f,
        Err(_) => return Response::builder().status(StatusCode::NOT_FOUND).body(Body::empty()).unwrap(),
    };

    let len = file.metadata().await.map(|m| m.len()).unwrap_or(0);
    let stream = tokio_util::io::ReaderStream::new(file);
    let body = Body::from_stream(stream);

    let mut headers = HeaderMap::new();
    headers.insert(header::CONTENT_TYPE, HeaderValue::from_static("application/vnd.android.package-archive"));
    headers.insert(header::CONTENT_DISPOSITION, HeaderValue::from_static("attachment; filename=\"moto-gps.apk\""));
    headers.insert(header::CONTENT_LENGTH, HeaderValue::from_str(&len.to_string()).unwrap());

    (StatusCode::OK, headers, body).into_response()
}
